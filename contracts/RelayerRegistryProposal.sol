// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "../submodules/tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";
import { TornadoVault } from "../submodules/tornado-lottery-period/contracts/vault/TornadoVault.sol";
import { IGovernanceVesting } from "../submodules/tornado-lottery-period/contracts/interfaces/IGovernanceVesting.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { TornadoProxy } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GovernanceStakingUpgradeOption1 } from "./governance-upgrade/GovernanceStakingUpgradeOption1.sol";
import { TornadoStakingRewards } from "./staking/TornadoStakingRewards.sol";
import { RelayerRegistry } from "./RelayerRegistry.sol";
import { TornadoProxyRegistryUpgrade } from "./tornado-proxy/TornadoProxyRegistryUpgrade.sol";
import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";

contract RelayerRegistryProposalOption1 is ImmutableGovernanceInformation {
  using SafeMath for uint256;

  address public constant GovernanceVesting = 0x179f48C78f57A3A78f0608cC9197B8972921d1D2;
  IERC20 public immutable tornToken = IERC20(TornTokenAddress);

  address public immutable gasCompLogic;
  address public immutable dataManagerProxy;
  address public immutable tornadoTrees;

  constructor(
    address tornadoTreesAddress,
    address gasCompLogicAddress,
    address dataManagerProxyAddress
  ) public {
    gasCompLogic = gasCompLogicAddress;
    dataManagerProxy = dataManagerProxyAddress;
    tornadoTrees = tornadoTreesAddress;
  }

  function executeProposal() external {
    uint256 totalOutflowsOfProposalExecutions = 120000000000000000000000 + 22916666666666666666666 + 54999999999999969408000 - 27e18;

    uint256 lockedTokenBalancesInGovernance = IGovernanceVesting(GovernanceVesting).released().sub(
      totalOutflowsOfProposalExecutions
    );

    address vault = address(new TornadoVault());
    address staking = address(new TornadoStakingRewards(GovernanceAddress, TornTokenAddress, lockedTokenBalancesInGovernance));

    LoopbackProxy(returnPayableGovernance()).upgradeTo(address(new GovernanceStakingUpgradeOption1(staking, vault)));

    GovernanceStakingUpgradeOption1 newGovernance = GovernanceStakingUpgradeOption1(GovernanceAddress);

    uint96[] memory test;
    address[] memory test2;

    address registryData = address(new RelayerRegistryData(dataManagerProxy, GovernanceAddress, test, test2));

    RelayerRegistry registry = new RelayerRegistry(registryData, GovernanceAddress, TornTokenAddress, staking);

    TornadoProxyRegistryUpgrade.Tornado[] memory test3;

    TornadoProxyRegistryUpgrade newTornadoProxy = new TornadoProxyRegistryUpgrade(
      address(registry),
      tornadoTrees,
      GovernanceAddress,
      test3
    );

    registry.registerProxy(address(newTornadoProxy));

    require(
      tornToken.transfer(
        address(newGovernance.userVault()),
        (tornToken.balanceOf(address(this))).sub(lockedTokenBalancesInGovernance)
      ),
      "TORN: transfer failed"
    );
  }
}
