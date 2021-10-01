// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { SafeMath } from "@openzeppelin/0.6/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/0.6/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/0.6/proxy/Initializable.sol";

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
  event StakeAddedToRelayer(address indexed relayer, uint256 indexed amountStakeAdded);
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

  function register(
    bytes32 ensHash,
    uint128 fee,
    uint128 stake,
    address[] memory toRegister
  ) external onlyENSOwner(ensHash) {
    RelayerMetadata storage metadata = getMetadataForRelayer[msg.sender];

    require(metadata.ensHash == bytes32(0), "registered already");
    require(stake.add(metadata.intData.balance) >= minStakeAmount, "!min_stake");

    _sendStakeToStaking(msg.sender, stake);
    emit StakeAddedToRelayer(msg.sender, stake);

    metadata.intData = RelayerIntegerMetadata(stake, fee);
    metadata.ensHash = ensHash;
    getMasterForSubaddress[msg.sender] = msg.sender;

    for (uint256 i = 0; i < toRegister.length; i++) {
      require(getMasterForSubaddress[toRegister[i]] == address(0), "can't steal an address");
      getMasterForSubaddress[toRegister[i]] = msg.sender;
    }

    emit NewRelayerRegistered(ensHash, msg.sender, fee, stake);
  }

  function registerSubaddress(address relayer, address subaddress) external {
    require(getMasterForSubaddress[msg.sender] == relayer, "only relayer");
    getMasterForSubaddress[subaddress] = relayer;
  }

  function unregisterSubaddress(address account, bool burn) external {
    require(msg.sender == account, "can only unregister self");
    if (burn) _nullifyBalance(getMasterForSubaddress[account]);
    getMasterForSubaddress[account] = address(0);
  }

  function stakeToRelayer(address relayer, uint128 stake) external {
    require(getMasterForSubaddress[relayer] == relayer, "!registered");
    _sendStakeToStaking(msg.sender, stake);
    emit StakeAddedToRelayer(relayer, stake);
    getMetadataForRelayer[relayer].intData.balance = uint128(stake.add(getMetadataForRelayer[relayer].intData.balance));
  }

  function burn(
    address sender,
    address relayer,
    address poolAddress
  ) external onlyRelayer(sender, relayer) onlyTornadoProxy {
    uint128 toBurn = uint128(RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress)));
    getMetadataForRelayer[relayer].intData.balance = uint128(getMetadataForRelayer[relayer].intData.balance.sub(toBurn));
    Staking.addBurnRewards(toBurn);
  }

  function setRelayerFee(address relayer, uint128 newFee) external onlyRelayer(msg.sender, relayer) {
    getMetadataForRelayer[relayer].intData.fee = newFee;
    emit RelayerChangedFee(relayer, uint128(newFee));
  }

  function setMinStakeAmount(uint256 minAmount) external onlyGovernanceCallForwarder {
    minStakeAmount = minAmount;
  }

  function registerProxy(address tornadoProxyAddress) external onlyGovernanceCallForwarder {
    tornadoProxy = tornadoProxyAddress;
  }

  function nullifyBalance(address relayer) external onlyGovernanceCallForwarder {
    _nullifyBalance(relayer);
  }

  function getRelayerFee(address relayer) external view returns (uint128) {
    return getMetadataForRelayer[relayer].intData.fee;
  }

  function isRelayer(address toResolve) external view returns (bool) {
    return getMasterForSubaddress[toResolve] != address(0);
  }

  function isRelayerRegistered(address relayer, address toResolve) external view returns (bool) {
    return getMasterForSubaddress[toResolve] == relayer;
  }

  function getRelayerEnsHash(address relayer) external view returns (bytes32) {
    return getMetadataForRelayer[relayer].ensHash;
  }

  function getRelayerBalance(address relayer) external view returns (uint128) {
    return getMetadataForRelayer[relayer].intData.balance;
  }

  function _nullifyBalance(address relayer) private {
    Staking.addBurnRewards(getMetadataForRelayer[relayer].intData.balance);
    getMetadataForRelayer[relayer].intData.balance = 0;
    emit RelayerBalanceNullified(relayer);
  }

  function _sendStakeToStaking(address sender, uint256 stake) private {
    require(torn.transferFrom(sender, address(Staking), stake), "transfer failed");
  }
}
