// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { GovernanceStakingUpgrade } from "../governance-upgrade/GovernanceStakingUpgrade.sol";
import { TornadoStakingRewards } from "../staking/TornadoStakingRewards.sol";
import { RelayerRegistry } from "../RelayerRegistry.sol";
import { TornadoRouter } from "../instances/TornadoRouter.sol";
import { TornadoInstances } from "../instances/TornadoInstances.sol";

import { TornadoProxy, ITornadoInstance } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

import { TornadoTrees } from "tornado-trees/contracts/TornadoTrees.sol";

contract MockProposal is ImmutableGovernanceInformation {
  using SafeMath for uint256;
  using Address for address;

  // ALREADY DEPLOYED
  address public constant tornadoTreesAddress = 0x527653eA119F3E6a1F5BD18fbF4714081D7B31ce;

  // FROM CREATE2 AND NEEDED
  address public constant expectedTornadoRouter = 0xbed362d2eE9AB8a1a4167F3020c018BF78DF2652;
  address public constant expectedTornadoInstances = 0xbed362d2eE9AB8a1a4167F3020c018BF78DF2652;
  address public constant expectedStaking = 0x0138b1Fc3AF55C0ec8Fde346591640a91022eE75;

  RelayerRegistry public constant Registry = RelayerRegistry(0xFd0086Cd33EB7B1610c1940637DbcEFa0552fD7A);
  IERC20 public constant tornToken = IERC20(TornTokenAddress);

  address public immutable oldTornadoProxy;
  address public immutable gasCompLogic;
  address public immutable tornadoVault;

  constructor(
    address oldTornadoProxyAddress,
    address gasCompLogicAddress,
    address vaultAddress
  ) public {
    oldTornadoProxy = oldTornadoProxyAddress;
    gasCompLogic = gasCompLogicAddress;
    tornadoVault = vaultAddress;
  }

  function executeProposal() external {
    require(expectedTornadoRouter.isContract(), "tornado router not deployed");
    require(expectedTornadoInstances.isContract(), "tornado instances not deployed");
    require(expectedStaking.isContract(), "staking contract not deployed");
    require(address(Registry).isContract(), "registry proxy not deployed");

    LoopbackProxy(returnPayableGovernance()).upgradeTo(
      address(new GovernanceStakingUpgrade(expectedStaking, gasCompLogic, tornadoVault))
    );

    Registry.initialize(GovernanceAddress, expectedStaking);

    TornadoTrees(tornadoTreesAddress).setTornadoProxyContract(expectedTornadoRouter);

    Registry.registerInstances(expectedTornadoRouter);

    TornadoInstances tornadoInstances = TornadoInstances(expectedTornadoRouter);

    disableOldProxy(tornadoInstances);

    tornadoInstances.setProtocolFee(1e15);
    tornadoInstances.setPeriodForTWAPOracle(5400);

    Registry.setMinStakeAmount(100 ether);
  }

  function disableOldProxy(TornadoInstances tornadoInstances) private {
    TornadoProxy oldProxy = TornadoProxy(oldTornadoProxy);

    TornadoProxy.Tornado memory currentTornado;
    ITornadoInstance currentInstance;
    uint256 bound = tornadoInstances.getNumberOfInstances();

    for (uint256 i = 0; i < bound; i++) {
      currentInstance = tornadoInstances.getInstanceForPoolId(i);
      (bool isERC20, IERC20 token, ) = oldProxy.instances(currentInstance);
      currentTornado = TornadoProxy.Tornado(
        currentInstance,
        TornadoProxy.Instance(isERC20, token, TornadoProxy.InstanceState.DISABLED)
      );

      oldProxy.updateInstance(currentTornado);
    }
  }
}
