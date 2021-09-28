// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { EnsResolve, ENS } from "./interfaces/EnsResolve.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";

interface ITornadoStakingRewards {
  function addStake(address sender, uint256 tornAmount) external;
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

contract RelayerRegistry is EnsResolve {
  using SafeMath for uint256;
  using SafeMath for uint128;

  address public immutable governance;

  ITornadoStakingRewards public immutable Staking;
  RelayerRegistryData public immutable RegistryData;

  uint256 public minStakeAmount;
  address public tornadoProxy;

  mapping(address => RelayerMetadata) public getMetadataForRelayer;

  event RelayerBalanceNullified(address indexed relayer);
  event RelayerChangedFee(address indexed relayer, uint248 indexed newFee);
  event StakeAddedToRelayer(address indexed relayer, uint256 indexed amountStakeAdded);
  event NewRelayerRegistered(bytes32 relayer, address indexed relayerAddress, uint248 indexed fee, uint256 indexed stakedAmount);

  constructor(
    address registryDataAddress,
    address tornadoGovernance,
    address stakingAddress
  ) public {
    RegistryData = RelayerRegistryData(registryDataAddress);
    governance = tornadoGovernance;
    Staking = ITornadoStakingRewards(stakingAddress);
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, "only governance");
    _;
  }

  modifier onlyTornadoProxy() {
    require(msg.sender == tornadoProxy, "only proxy");
    _;
  }

  modifier onlyENSOwner(bytes32 node) {
    require(msg.sender == ENS(ensAddress).owner(node), "only ens owner");
    _;
  }

  modifier onlyRelayer(address relayer) {
    require(getMetadataForRelayer[relayer].addresses[msg.sender], "only relayer");
    _;
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

    for (uint256 i = 1; i < toRegister.length + 1; i++) {
      metadata.addresses[toRegister[i]] = true;
    }

    emit NewRelayerRegistered(ensHash, msg.sender, fee, stake);
  }

  function setRelayerFee(address relayer, uint128 newFee) external onlyRelayer(relayer) {
    getMetadataForRelayer[relayer].intData.fee = newFee;
    emit RelayerChangedFee(relayer, uint128(newFee));
  }

  function burn(
    address sender,
    address relayer,
    address poolAddress
  ) external onlyRelayer(sender) {
    _burn(relayer, poolAddress);
  }

  function setMinStakeAmount(uint256 minAmount) external onlyGovernance {
    minStakeAmount = minAmount;
  }

  function registerProxy(address tornadoProxyAddress) external onlyGovernance {
    tornadoProxy = tornadoProxyAddress;
  }

  function nullifyBalance(address relayer) external onlyGovernance {
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
    Staking.addStake(relayer, stake);
    emit StakeAddedToRelayer(relayer, stake);
  }

  function _burn(address relayer, address poolAddress) private onlyTornadoProxy {
    getMetadataForRelayer[relayer].intData.balance = uint128(
      getMetadataForRelayer[relayer].intData.balance.sub(
        uint128(RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress)))
      )
    );
  }
}
