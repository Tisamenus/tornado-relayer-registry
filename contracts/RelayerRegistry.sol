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

struct RelayerMetadata {
  uint256 balance;
  bytes32 ensHash;
}

/**
 * @notice Registry contract, one of the main contracts of this protocol upgrade.
 *         The contract should store relayers' addresses and data attributed to the
 *         master address of the relayer. This data includes the relayers' stake
 *         he charges.
 * @dev CONTRACT RISKS:
 *      - if setter functions are compromised, relayer metadata would be at risk, including the noted amount of his balance
 *      - if burn function is compromised, relayers run the risk of being unable to handle withdrawals
 *      - the above risk also applies to the nullify balance function
 * */
contract RelayerRegistry is Initializable {
  using SafeMath for uint256;

  address public constant ensAddress = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
  address public governanceCallForwarder;

  IERC20 public torn;
  ITornadoStakingRewards public Staking;
  RelayerRegistryData public RegistryData;

  uint256 public minStakeAmount;
  address public tornadoProxy;

  mapping(address => RelayerMetadata) public getMetadataForRelayer;
  mapping(address => address) public getMasterForWorker;

  event RelayerBalanceNullified(address indexed relayer);
  event WorkerRegistered(address indexed worker);
  event WorkerUnregistered(address indexed worker);
  event StakeAddedToRelayer(address indexed relayer, uint256 indexed amountStakeAdded);
  event StakeBurned(address indexed relayer, uint256 indexed amountBurned);
  event NewMinimumStakeAmount(uint256 indexed minStakeAmount);
  event NewProxyRegistered(address indexed tornadoProxy);
  event NewRelayerRegistered(bytes32 relayer, address indexed relayerAddress, uint256 indexed stakedAmount);

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
    require(getMasterForWorker[sender] == relayer, "only relayer");
    _;
  }

  /**
   * @notice initialize function for upgradeability
   * @dev this contract will be deployed behind a proxy and should not assign values at logic address,
   *      params left out because self explainable
   * */
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
   * @notice This function should register a master address and optionally a set of workeres for a relayer + metadata
   * @dev Relayer can't steal other relayers workeres since they are registered, and a wallet (msg.sender check) can always unregister itself
   * @param ensHash ensHash of the relayer
   * @param stake the initial amount of stake in TORN the relayer is depositing
   * */
  function register(
    bytes32 ensHash,
    uint256 stake,
    address[] memory workersToRegister
  ) external onlyENSOwner(ensHash) {
    require(getMasterForWorker[msg.sender] == address(0), "cant register again");
    RelayerMetadata storage metadata = getMetadataForRelayer[msg.sender];

    require(metadata.ensHash == bytes32(0), "registered already");
    require(stake >= minStakeAmount, "!min_stake");

    _sendStakeToStaking(msg.sender, stake);
    emit StakeAddedToRelayer(msg.sender, stake);

    metadata.balance = stake;
    metadata.ensHash = ensHash;
    getMasterForWorker[msg.sender] = msg.sender;

    for (uint256 i = 0; i < workersToRegister.length; i++) {
      require(getMasterForWorker[workersToRegister[i]] == address(0), "can't steal an address");
      getMasterForWorker[workersToRegister[i]] = msg.sender;
    }

    emit NewRelayerRegistered(ensHash, msg.sender, stake);
  }

  /**
   * @notice This function should allow relayers to register more workeres
   * @param relayer Relayer which should send message from any worker which is already registered
   * @param worker Address to register
   * */
  function registerWorker(address relayer, address worker) external {
    require(getMasterForWorker[msg.sender] == relayer, "only relayer");
    require(getMasterForWorker[worker] == address(0), "can't steal an address");
    getMasterForWorker[worker] = relayer;
    emit WorkerRegistered(worker);
  }

  /**
   * @notice This function should allow anybody to unregister an address they own
   * @dev designed this way as to allow someone to unregister themselves in case a relayer misbehaves
   *      - this should be followed by an action like burning relayer stake
   *      - there was an option of allowing the sender to burn relayer stake in case of malicious behaviour, this feature was not included in the end
   * */
  function unregisterWorker(address worker) external {
    if (worker != msg.sender) require(getMasterForWorker[worker] == msg.sender, "only owner of worker");
    getMasterForWorker[msg.sender] = address(0);
    emit WorkerUnregistered(msg.sender);
  }

  /**
   * @notice This function should allow anybody to stake to a relayer more TORN
   * @param relayer Relayer main address to stake to
   * @param stake Stake to be added to relayer
   * */
  function stakeToRelayer(address relayer, uint256 stake) external {
    require(getMasterForWorker[relayer] == relayer, "!registered");
    _sendStakeToStaking(msg.sender, stake);
    getMetadataForRelayer[relayer].balance = uint256(stake.add(getMetadataForRelayer[relayer].balance));
    emit StakeAddedToRelayer(relayer, stake);
  }

  /**
   * @notice This function should burn some relayer stake on withdraw and notify staking of this
   * @dev IMPORTANT FUNCTION:
   *      - This should be only called by the tornado proxy
   *      - Should revert if relayer does not call proxy from valid worker
   *      - Should not overflow
   *      - Should underflow and revert (SafeMath) on not enough stake (balance)
   * @param sender worker to check sender == relayer
   * @param relayer address of relayer who's stake is being burned
   * @param poolAddress instance address to get proper fee
   * */
  function burn(
    address sender,
    address relayer,
    address poolAddress
  ) external onlyRelayer(sender, relayer) onlyTornadoProxy {
    uint256 toBurn = RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress));
    getMetadataForRelayer[relayer].balance = getMetadataForRelayer[relayer].balance.sub(toBurn);
    Staking.addBurnRewards(toBurn);
    emit StakeBurned(relayer, toBurn);
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
   * @notice This function should check if a worker is associated with a relayer
   * @param toResolve address to check
   * @return true if is associated
   * */
  function isRelayer(address toResolve) external view returns (bool) {
    return getMasterForWorker[toResolve] != address(0);
  }

  /**
   * @notice This function should check if a worker is registered to the relayer stated
   * @param relayer relayer to check
   * @param toResolve address to check
   * @return true if registered
   * */
  function isRelayerRegistered(address relayer, address toResolve) external view returns (bool) {
    return getMasterForWorker[toResolve] == relayer;
  }

  /**
   * @notice This function should get a relayers ensHash
   * @param relayer address to fetch for
   * @return relayer's ensHash
   * */
  function getRelayerEnsHash(address relayer) external view returns (bytes32) {
    return getMetadataForRelayer[getMasterForWorker[relayer]].ensHash;
  }

  /**
   * @notice This function should get a relayers balance
   * @param relayer relayer who's balance is to fetch
   * @return relayer's balance
   * */
  function getRelayerBalance(address relayer) external view returns (uint256) {
    return getMetadataForRelayer[getMasterForWorker[relayer]].balance;
  }

  /**
   * @notice This function nullify a relayers balance
   * @dev IMPORTANT FUNCTION:
   *      - Should add his entire rest balance as burned rewards
   *      - Should nullify the balance
   * @param relayer relayer who's balance is to nullify
   * */
  function _nullifyBalance(address relayer) private {
    address masterAddress = getMasterForWorker[relayer];
    Staking.addBurnRewards(getMetadataForRelayer[masterAddress].balance);
    getMetadataForRelayer[masterAddress].balance = 0;
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
