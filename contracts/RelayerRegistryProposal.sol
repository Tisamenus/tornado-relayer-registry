// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "../submodules/tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

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
  using Address for address;

  // ALREADY DEPLOYED
  address public constant tornadoTreesAddress = 0x527653eA119F3E6a1F5BD18fbF4714081D7B31ce;

  // FROM CREATE2 AND NEEDED
  address public constant expectedNewTornadoProxy = 0x7c60281516215A366194608C8bC5186c13Cfc9Ce;
  address public constant expectedStaking = 0x1907232F0462353cc2296d665454723ff2944C59;
  RelayerRegistry public constant Registry = RelayerRegistry(0x8cF67c498906c85DC52AcAAD926638552463D918);

  IERC20 public constant tornToken = IERC20(TornTokenAddress);

  TornadoInstancesData public immutable InstancesData;

  address public immutable oldTornadoProxy;
  address public immutable gasCompLogic;
  address public immutable tornadoVault;

  constructor(
    address oldTornadoProxyAddress,
    address tornadoInstancesDataAddress,
    address gasCompLogicAddress,
    address vaultAddress
  ) public {
    oldTornadoProxy = oldTornadoProxyAddress;
    InstancesData = TornadoInstancesData(tornadoInstancesDataAddress);
    gasCompLogic = gasCompLogicAddress;
    tornadoVault = vaultAddress;
  }

  function executeProposal() external {
    require(expectedNewTornadoProxy.isContract(), "tornado proxy not deployed");
    require(expectedStaking.isContract(), "staking contract not deployed");
    require(address(Registry).isContract(), "registry proxy not deployed");

    LoopbackProxy(returnPayableGovernance()).upgradeTo(
      address(new GovernanceStakingUpgrade(expectedStaking, gasCompLogic, tornadoVault))
    );

    Registry.initialize(GovernanceAddress, expectedStaking, address(tornToken));

    disableOldProxy();

    TornadoTrees(tornadoTreesAddress).setTornadoProxyContract(expectedNewTornadoProxy);

    Registry.registerProxy(expectedNewTornadoProxy);

    TornadoProxyRegistryUpgrade TornadoProxy = TornadoProxyRegistryUpgrade(expectedNewTornadoProxy);

    (TornadoProxy.DataManager()).initialize(address(TornadoProxy));

    TornadoProxy.setProtocolFee(1e15);
    TornadoProxy.setPeriodForTWAPOracle(5400);

    Registry.setMinStakeAmount(100 ether);
  }

  function disableOldProxy() private {
    TornadoProxy oldProxy = TornadoProxy(oldTornadoProxy);

    TornadoProxy.Tornado[] memory Instances = InstancesData.getInstances();

    for (uint256 i = 0; i < Instances.length; i++) {
      oldProxy.updateInstance(Instances[i]);
    }
  }
}
