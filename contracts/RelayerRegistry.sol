// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/0.6.x/proxy/Initializable.sol";

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
  mapping(address => bool) addresses;
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
    require(getMetadataForRelayer[relayer].addresses[sender], "only relayer");
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

  function stakeToRelayer(address relayer, uint128 stake) external {
    require(getMetadataForRelayer[relayer].addresses[relayer], "!registered");
    _stakeToRelayer(relayer, stake);
    getMetadataForRelayer[relayer].intData.balance = uint128(stake.add(getMetadataForRelayer[relayer].intData.balance));
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

    _stakeToRelayer(msg.sender, stake);

    metadata.intData = RelayerIntegerMetadata(stake, fee);
    metadata.addresses[msg.sender] = true;
    metadata.ensHash = ensHash;

    for (uint256 i = 0; i < toRegister.length; i++) {
      metadata.addresses[toRegister[i]] = true;
    }

    emit NewRelayerRegistered(ensHash, msg.sender, fee, stake);
  }

  function setRelayerFee(address relayer, uint128 newFee) external onlyRelayer(msg.sender, relayer) {
    getMetadataForRelayer[relayer].intData.fee = newFee;
    emit RelayerChangedFee(relayer, uint128(newFee));
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

  function setMinStakeAmount(uint256 minAmount) external onlyGovernanceCallForwarder {
    minStakeAmount = minAmount;
  }

  function registerProxy(address tornadoProxyAddress) external onlyGovernanceCallForwarder {
    tornadoProxy = tornadoProxyAddress;
  }

  function nullifyBalance(address relayer) external onlyGovernanceCallForwarder {
    getMetadataForRelayer[relayer].intData.balance = 0;
    emit RelayerBalanceNullified(relayer);
  }

  function getRelayerFee(address relayer) external view returns (uint128) {
    return getMetadataForRelayer[relayer].intData.fee;
  }

  function isRelayerRegistered(address relayer, address toResolve) external view returns (bool) {
    return getMetadataForRelayer[relayer].addresses[toResolve];
  }

  function getRelayerEnsHash(address relayer) external view returns (bytes32) {
    return getMetadataForRelayer[relayer].ensHash;
  }

  function getRelayerBalance(address relayer) external view returns (uint128) {
    return getMetadataForRelayer[relayer].intData.balance;
  }

  function _stakeToRelayer(address relayer, uint256 stake) private {
    require(torn.transferFrom(relayer, address(Staking), stake), "transfer failed");
    emit StakeAddedToRelayer(relayer, stake);
  }
}
