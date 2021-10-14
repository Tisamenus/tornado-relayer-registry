// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "../submodules/tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GovernanceStakingUpgrade } from "./governance-upgrade/GovernanceStakingUpgrade.sol";
import { TornadoStakingRewards } from "./staking/TornadoStakingRewards.sol";
import { RegistryDataManager } from "./registry-data/RegistryDataManager.sol";
import { TornadoInstancesData } from "./tornado-proxy/TornadoInstancesData.sol";
import { RelayerRegistry } from "./RelayerRegistry.sol";
import { TornadoProxyRegistryUpgrade } from "./tornado-proxy/TornadoProxyRegistryUpgrade.sol";

import { TornadoProxy } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

import { TornadoTrees } from "tornado-trees/contracts/TornadoTrees.sol";

contract RelayerRegistryProposal is ImmutableGovernanceInformation {
  using SafeMath for uint256;

  address public constant tornadoTreesAddress = 0x527653eA119F3E6a1F5BD18fbF4714081D7B31ce;
  IERC20 public constant tornToken = IERC20(TornTokenAddress);

  RelayerRegistry public immutable Registry;
  TornadoInstancesData public immutable InstancesData;

  address public immutable oldTornadoProxy;
  address public immutable newTornadoProxy;
  address public immutable gasCompLogic;
  address public immutable tornadoVault;
  address public immutable staking;

  constructor(
    address registryAddress,
    address oldTornadoProxyAddress,
    address newTornadoProxyAddress,
    address stakingAddress,
    address tornadoInstancesDataAddress,
    address gasCompLogicAddress,
    address vaultAddress
  ) public {
    Registry = RelayerRegistry(registryAddress);
    newTornadoProxy = newTornadoProxyAddress;
    oldTornadoProxy = oldTornadoProxyAddress;
    staking = stakingAddress;
    InstancesData = TornadoInstancesData(tornadoInstancesDataAddress);
    gasCompLogic = gasCompLogicAddress;
    tornadoVault = vaultAddress;
  }

  function executeProposal() external {
    LoopbackProxy(returnPayableGovernance()).upgradeTo(
      address(new GovernanceStakingUpgrade(staking, gasCompLogic, tornadoVault))
    );

    Registry.initialize(GovernanceAddress, staking, address(tornToken));

    TornadoTrees(tornadoTreesAddress).setTornadoProxyContract(newTornadoProxy);

    Registry.registerProxy(newTornadoProxy);

    TornadoProxyRegistryUpgrade TornadoProxy = TornadoProxyRegistryUpgrade(newTornadoProxy);

    TornadoProxy.setProtocolFee(1e15);
    TornadoProxy.setPeriodForTWAPOracle(5400);

    Registry.setMinStakeAmount(100 ether);

    disableOldProxy();
  }

  function disableOldProxy() private {
    TornadoProxy oldProxy = TornadoProxy(oldTornadoProxy);

    TornadoProxy.Tornado[] memory Instances = InstancesData.getInstances();

    for (uint256 i = 0; i < Instances.length; i++) {
      oldProxy.updateInstance(Instances[i]);
    }
  }
}
