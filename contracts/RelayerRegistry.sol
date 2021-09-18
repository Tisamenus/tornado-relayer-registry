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

struct RelayerMetadata {
  bool isRegistered;
  uint248 fee;
}

contract RelayerRegistry is EnsResolve {
  using SafeMath for uint256;

  address public immutable governance;

  ITornadoStakingRewards public immutable staking;
  IERC20 public immutable torn;
  RelayerRegistryData public immutable RegistryData;

  uint256 public minStakeAmount;
  address public tornadoProxy;

  mapping(bytes32 => uint256) public getBalanceForRelayer;
  mapping(bytes32 => RelayerMetadata) public getMetadataForRelayer;
  mapping(address => bytes32) public getRelayerForAddress;

  constructor(
    address registryDataAddress,
    address tornadoGovernance,
    address tornAddress,
    address stakingAddress
  ) public {
    RegistryData = RelayerRegistryData(registryDataAddress);
    governance = tornadoGovernance;
    torn = IERC20(tornAddress);
    staking = ITornadoStakingRewards(stakingAddress);
  }

  modifier onlyGovernance() {
    require(msg.sender == governance);
    _;
  }

  modifier onlyTornadoProxy() {
    require(msg.sender == tornadoProxy);
    _;
  }

  modifier onlyRelayer(bytes32 relayer) {
    require(msg.sender == resolve(relayer));
    _;
  }

  function register(
    bytes32 ensName,
    uint256 stake,
    RelayerMetadata memory metadata
  ) external onlyRelayer(ensName) {
    require(!getMetadataForRelayer[ensName].isRegistered, "registered");
    if (!metadata.isRegistered) metadata.isRegistered = true;
    getMetadataForRelayer[ensName] = metadata;
    getRelayerForAddress[resolve(ensName)] = ensName;
    stakeToRelayer(ensName, stake);
  }

  function burn(bytes32 relayer, address poolAddress) external onlyTornadoProxy {
    getBalanceForRelayer[relayer] = getBalanceForRelayer[relayer].sub(
      RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress))
    );
  }

  function setMinStakeAmount(uint256 minAmount) external onlyGovernance {
    minStakeAmount = minAmount;
  }

  function registerProxy(address tornadoProxyAddress) external onlyGovernance {
    require(tornadoProxy == address(0));
    tornadoProxy = tornadoProxyAddress;
  }

  function nullifyBalance(bytes32 relayer) external onlyGovernance {
    getBalanceForRelayer[relayer] = 0;
  }

  function getRelayerFee(bytes32 relayer) external view returns (uint256) {
    return getMetadataForRelayer[relayer].fee;
  }

  function isRelayerRegistered(bytes32 relayer) external view returns (bool) {
    return getMetadataForRelayer[relayer].isRegistered;
  }

  function stakeToRelayer(bytes32 relayer, uint256 stake) public {
    require(getMetadataForRelayer[relayer].isRegistered, "!registered");
    require(stake.add(getBalanceForRelayer[relayer]) >= minStakeAmount, "!min_stake");
    staking.addStake(resolve(relayer), stake);
    getBalanceForRelayer[relayer] += stake;
  }
}
