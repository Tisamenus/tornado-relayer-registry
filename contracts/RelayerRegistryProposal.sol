// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "../submodules/tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GovernanceStakingUpgrade } from "./governance-upgrade/GovernanceStakingUpgrade.sol";
import { TornadoStakingRewards } from "./staking/TornadoStakingRewards.sol";
import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { TornadoInstancesData } from "./tornado-proxy/TornadoInstancesData.sol";
import { RegistryCallForwarder } from "./governance-upgrade/RegistryCallForwarder.sol";

import { TornadoProxy } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

import { TornadoTrees } from "tornado-trees/contracts/TornadoTrees.sol";

contract RelayerRegistryProposal is ImmutableGovernanceInformation {
  using SafeMath for uint256;

  address public constant TornadoTreesAddress = 0x527653eA119F3E6a1F5BD18fbF4714081D7B31ce;
  IERC20 public constant tornToken = IERC20(TornTokenAddress);

  RegistryCallForwarder public immutable Forwarder;
  TornadoStakingRewards public immutable Staking;
  TornadoInstancesData public immutable InstancesData;

  address public immutable oldTornadoProxy;
  address public immutable newTornadoProxy;
  address public immutable gasCompLogic;
  address public immutable tornadoVault;

  constructor(
    address callForwarderAddress,
    address oldTornadoProxyAddress,
    address newTornadoProxyAddress,
    address stakingAddress,
    address tornadoInstancesDataAddress,
    address gasCompLogicAddress,
    address vaultAddress
  ) public {
    Forwarder = RegistryCallForwarder(callForwarderAddress);
    newTornadoProxy = newTornadoProxyAddress;
    oldTornadoProxy = oldTornadoProxyAddress;
    Staking = TornadoStakingRewards(stakingAddress);
    InstancesData = TornadoInstancesData(tornadoInstancesDataAddress);
    gasCompLogic = gasCompLogicAddress;
    tornadoVault = vaultAddress;
  }

  function executeProposal() external {
    LoopbackProxy(returnPayableGovernance()).upgradeTo(
      address(new GovernanceStakingUpgrade(address(Staking), address(Forwarder), gasCompLogic, tornadoVault))
    );

    TornadoTrees(TornadoTreesAddress).setTornadoProxyContract(newTornadoProxy);

    Forwarder.forwardRegisterProxy(newTornadoProxy);

    RelayerRegistryData RegistryData = Forwarder.getRegistryData();

    RegistryData.setProtocolFee(1e15);
    RegistryData.setPeriodForTWAPOracle(5400);

    Staking.registerRelayerRegistry(address(Forwarder.Registry()));

    Forwarder.forwardSetMinStakeAmount(100 ether);

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
