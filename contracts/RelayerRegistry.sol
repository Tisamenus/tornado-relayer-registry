// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";

interface ITornadoStakingRewards {
  function addBurnRewards(uint256 amount) external;
}

interface IENS {
  function owner(bytes32 node) external view returns (address);
}

struct RelayerIntegerMetadata {
  uint128 balance;
  uint128 fee;
}

struct RelayerMetadata {
  RelayerIntegerMetadata intData;
  bytes32 ensHash;
}

contract RelayerRegistry is Initializable {
  using SafeMath for uint256;
  using SafeMath for uint128;

  address public constant ensAddress = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
  address public governanceCallForwarder;

  IERC20 public torn;
  ITornadoStakingRewards public Staking;
  RelayerRegistryData public RegistryData;

  uint256 public minStakeAmount;
  address public tornadoProxy;

  mapping(address => RelayerMetadata) public getMetadataForRelayer;
  mapping(address => address) public getMasterForSubaddress;

  event RelayerBalanceNullified(address indexed relayer);
  event RelayerChangedFee(address indexed relayer, uint248 indexed newFee);
  event SubaddressRegistered(address indexed subaddress);
  event SubaddressUnregistered(address indexed subaddress);
  event StakeAddedToRelayer(address indexed relayer, uint256 indexed amountStakeAdded);
  event StakeBurned(address indexed relayer, uint256 indexed amountBurned);
  event NewMinimumStakeAmount(uint256 indexed minStakeAmount);
  event NewProxyRegistered(address indexed tornadoProxy);
  event NewRelayerRegistered(bytes32 relayer, address indexed relayerAddress, uint248 indexed fee, uint256 indexed stakedAmount);

  modifier onlyGovernanceCallForwarder() {
    require(msg.sender == governanceCallForwarder, "only governance");
    _;
  }

  modifier onlyTornadoProxy() {
    require(msg.sender == tornadoProxy, "only proxy");
    _;
  }

  modifier onlyENSOwner(bytes32 node) {
    require(msg.sender == IENS(ensAddress).owner(node), "only ens owner");
    _;
  }

  modifier onlyRelayer(address sender, address relayer) {
    require(getMasterForSubaddress[sender] == relayer, "only relayer");
    _;
  }

  function initialize(
    address registryDataAddress,
    address tornadoGovernance,
    address stakingAddress,
    address tornTokenAddress
  ) external initializer {
    RegistryData = RelayerRegistryData(registryDataAddress);
    governanceCallForwarder = tornadoGovernance;
    Staking = ITornadoStakingRewards(stakingAddress);
    torn = IERC20(tornTokenAddress);
  }

  /**
   * @notice This function should register a master address and optionally a set of subaddresses for a relayer + metadata
   * @dev Relayer can't steal other relayers subaddresses since they are registered, and a wallet (msg.sender check) can always unregister itself
   * @param ensHash ensHash of the relayer
   * @param fee the fee the relayer will charge for withdrawals
   * @param stake the initial amount of stake in TORN the relayer is depositing
   * */
  function register(
    bytes32 ensHash,
    uint128 fee,
    uint128 stake,
    address[] memory subaddressesToRegister
  ) external onlyENSOwner(ensHash) {
    RelayerMetadata storage metadata = getMetadataForRelayer[msg.sender];

    require(metadata.ensHash == bytes32(0), "registered already");
    require(stake.add(metadata.intData.balance) >= minStakeAmount, "!min_stake");

    _sendStakeToStaking(msg.sender, stake);
    emit StakeAddedToRelayer(msg.sender, stake);

    metadata.intData = RelayerIntegerMetadata(stake, fee);
    metadata.ensHash = ensHash;
    getMasterForSubaddress[msg.sender] = msg.sender;

    for (uint256 i = 0; i < subaddressesToRegister.length; i++) {
      require(getMasterForSubaddress[subaddressesToRegister[i]] == address(0), "can't steal an address");
      getMasterForSubaddress[subaddressesToRegister[i]] = msg.sender;
    }

    emit NewRelayerRegistered(ensHash, msg.sender, fee, stake);
  }

  /**
   * @notice This function should allow relayers to register more subaddresses
   * @param relayer Relayer which should send message from any subaddress which is already registered
   * @param subaddress Address to register
   * */
  function registerSubaddress(address relayer, address subaddress) external {
    require(getMasterForSubaddress[msg.sender] == relayer, "only relayer");
    getMasterForSubaddress[subaddress] = relayer;
    emit SubaddressRegistered(subaddress);
  }

  /**
   * @notice This function should allow anybody to unregister an address they own
   * @dev designed this way as to allow someone to unregister themselves in case a relayer misbehaves
   *      - this should be followed by an action like burning relayer stake
   *      - there was an option of allowing the sender to burn relayer stake in case of malicious behaviour, this feature was not included in the end
   * @param subaddress Address to unregister
   * */
  function unregisterSubaddress(address subaddress) external {
    require(msg.sender == subaddress, "can only unregister self");
    getMasterForSubaddress[subaddress] = address(0);
    emit SubaddressUnregistered(subaddress);
  }

  /**
   * @notice This function should allow anybody to stake to a relayer more TORN
   * @param relayer Relayer main address to stake to
   * @param stake Stake to be added to relayer
   * */
  function stakeToRelayer(address relayer, uint128 stake) external {
    require(getMasterForSubaddress[relayer] == relayer, "!registered");
    _sendStakeToStaking(msg.sender, stake);
    getMetadataForRelayer[relayer].intData.balance = uint128(stake.add(getMetadataForRelayer[relayer].intData.balance));
    emit StakeAddedToRelayer(relayer, stake);
  }

  /**
   * @notice This function should burn some relayer stake on withdraw and notify staking of this
   * @dev IMPORTANT FUNCTION:
   *      - This should be only called by the tornado proxy
   *      - Should revert if relayer does not call proxy from valid subaddress
   *      - Should not overflow
   *      - Requirement with uint128 = total supply * 0.01 of an ERC20 should not exceed 1e38
   *      - Should underflow and revert (SafeMath) on not enough stake (balance)
   * @param sender subaddress to check sender == relayer
   * @param relayer address of relayer who's stake is being burned
   * @param poolAddress instance address to get proper fee
   * */
  function burn(
    address sender,
    address relayer,
    address poolAddress
  ) external onlyRelayer(sender, relayer) onlyTornadoProxy {
    uint128 toBurn = uint128(RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress)));
    getMetadataForRelayer[relayer].intData.balance = uint128(getMetadataForRelayer[relayer].intData.balance.sub(toBurn));
    Staking.addBurnRewards(toBurn);
    emit StakeBurned(relayer, toBurn);
  }

  /**
   * @notice This function should allow relayers to set their fee
   * @dev There is the possiblity of discussing a cooldown period
   * @param relayer Relayer main address to stake to
   * @param stake Stake to be added to relayer
   * */
  function setRelayerFee(address relayer, uint128 newFee) external onlyRelayer(msg.sender, relayer) {
    getMetadataForRelayer[relayer].intData.fee = newFee;
    emit RelayerChangedFee(relayer, uint128(newFee));
  }

  /**
   * @notice This function should allow governance to set the minimum stake amount
   * @param minAmount new minimum stake amount
   * */
  function setMinStakeAmount(uint256 minAmount) external onlyGovernanceCallForwarder {
    minStakeAmount = minAmount;
    emit NewMinimumStakeAmount(minAmount);
  }

  /**
   * @notice This function should allow governance to set a new tornado proxy address
   * @param tornadoProxyAddress address of the new proxy
   * */
  function registerProxy(address tornadoProxyAddress) external onlyGovernanceCallForwarder {
    tornadoProxy = tornadoProxyAddress;
    emit NewProxyRegistered(tornadoProxyAddress);
  }

  /**
   * @notice This function should allow governance to nullify a relayers balance
   * @dev IMPORTANT FUNCTION
   * @param relayer address of relayer who's balance is to nullify
   * */
  function nullifyBalance(address relayer) external onlyGovernanceCallForwarder {
    _nullifyBalance(relayer);
  }

  /**
   * @notice This function should return a relayers fee
   * @param relayer address of relayer who's fee is to fetch
   * @return the fee
   * */
  function getRelayerFee(address relayer) external view returns (uint128) {
    return getMetadataForRelayer[relayer].intData.fee;
  }

  /**
   * @notice This function should check if a subaddress is associated with a relayer
   * @param toResolve address to check
   * @return true if is associated
   * */
  function isRelayer(address toResolve) external view returns (bool) {
    return getMasterForSubaddress[toResolve] != address(0);
  }

  /**
   * @notice This function should check if a subaddress is registered to the relayer stated
   * @param relayer relayer to check
   * @param toResolve address to check
   * @return true if registered
   * */
  function isRelayerRegistered(address relayer, address toResolve) external view returns (bool) {
    return getMasterForSubaddress[toResolve] == relayer;
  }

  /**
   * @notice This function should get a relayers ensHash
   * @param relayer address to fetch for
   * @return relayer's ensHash
   * */
  function getRelayerEnsHash(address relayer) external view returns (bytes32) {
    return getMetadataForRelayer[relayer].ensHash;
  }

  /**
   * @notice This function should get a relayers balance
   * @param relayer relayer who's balance is to fetch
   * @return relayer's balance
   * */
  function getRelayerBalance(address relayer) external view returns (uint128) {
    return getMetadataForRelayer[relayer].intData.balance;
  }

  /**
   * @notice This function nullify a relayers balance
   * @dev IMPORTANT FUNCTION:
   *      - Should add his entire rest balance as burned rewards
   *      - Should nullify the balance
   * @param relayer relayer who's balance is to nullify
   * */
  function _nullifyBalance(address relayer) private {
    Staking.addBurnRewards(getMetadataForRelayer[relayer].intData.balance);
    getMetadataForRelayer[relayer].intData.balance = 0;
    emit RelayerBalanceNullified(relayer);
  }

  /**
   * @notice This function should send TORN to Staking
   * @param sender address to transfer from
   * @param stake amount to transfer
   * */
  function _sendStakeToStaking(address sender, uint256 stake) private {
    require(torn.transferFrom(sender, address(Staking), stake), "transfer failed");
  }
}
