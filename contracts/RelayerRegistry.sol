// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { EnsResolve } from "./interfaces/EnsResolve.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";

interface ITornadoStakingRewards {
  function addStake(address sender, uint256 tornAmount) external;
}

interface IENS {
  function owner(bytes32 node) external view returns (address);
}

struct RelayerMetadata {
  bool isRegistered;
  uint248 fee;
}

contract RelayerRegistry is EnsResolve {
  using SafeMath for uint256;

  address public immutable governance;

  ITornadoStakingRewards public immutable Staking;
  RelayerRegistryData public immutable RegistryData;

  uint256 public minStakeAmount;
  address public tornadoProxy;

  mapping(bytes32 => uint256) public getBalanceForRelayer;
  mapping(bytes32 => RelayerMetadata) public getMetadataForRelayer;
  mapping(address => bytes32) public getRelayerForAddress;

  event RelayerChangedFee(bytes32 indexed relayer, uint248 indexed newFee);
  event RelayerBalanceNullified(bytes32 indexed relayer);
  event NewRelayerRegistered(bytes32 indexed relayer, uint248 indexed fee, uint256 indexed stakedAmount);
  event StakeAddedToRelayer(bytes32 indexed relayer, uint256 indexed amountStakeAdded);

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

  modifier onlyRelayer(bytes32 relayer) {
    require(msg.sender == resolve(relayer), "only relayer");
    _;
  }

  function register(
    bytes32 ensName,
    uint256 stake,
    RelayerMetadata memory metadata
  ) external onlyRelayer(ensName) {
    require(!getMetadataForRelayer[ensName].isRegistered, "registered");
    require(stake.add(getBalanceForRelayer[ensName]) >= minStakeAmount, "!min_stake");
    if (!metadata.isRegistered) metadata.isRegistered = true;
    getMetadataForRelayer[ensName] = metadata;
    getRelayerForAddress[resolve(ensName)] = ensName;
    stakeToRelayer(ensName, stake);
    emit NewRelayerRegistered(ensName, metadata.fee, stake);
  }

  function setRelayerFee(bytes32 ensName, uint256 newFee) external onlyRelayer(ensName) {
    getMetadataForRelayer[ensName].fee = uint248(newFee);
    emit RelayerChangedFee(ensName, uint248(newFee));
  }

  function burn(address relayer, address poolAddress) external onlyTornadoProxy {
    bytes32 relayerEnsName = getRelayerForAddress[relayer];

    getBalanceForRelayer[relayerEnsName] = getBalanceForRelayer[relayerEnsName].sub(
      RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress))
    );
  }

  function setMinStakeAmount(uint256 minAmount) external onlyGovernance {
    minStakeAmount = minAmount;
  }

  function registerProxy(address tornadoProxyAddress) external onlyGovernance {
    require(tornadoProxy == address(0), "proxy already registered");
    tornadoProxy = tornadoProxyAddress;
  }

  function nullifyBalance(bytes32 relayer) external onlyGovernance {
    getBalanceForRelayer[relayer] = 0;
    emit RelayerBalanceNullified(relayer);
  }

  function getRelayerFee(bytes32 relayer) external view returns (uint256) {
    return getMetadataForRelayer[relayer].fee;
  }

  function isRelayerRegistered(bytes32 relayer) external view returns (bool) {
    return getMetadataForRelayer[relayer].isRegistered;
  }

  function stakeToRelayer(bytes32 relayer, uint256 stake) public {
    require(getMetadataForRelayer[relayer].isRegistered, "!registered");
    Staking.addStake(resolve(relayer), stake);
    getBalanceForRelayer[relayer] += stake;
    emit StakeAddedToRelayer(relayer, stake);
  }
}
