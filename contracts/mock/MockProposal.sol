// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "../../submodules/tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { GovernanceStakingUpgrade } from "../governance-upgrade/GovernanceStakingUpgrade.sol";
import { TornadoStakingRewards } from "../staking/TornadoStakingRewards.sol";
import { RelayerRegistry } from "../RelayerRegistry.sol";
import { TornadoProxyRegistryUpgrade } from "../tornado-proxy/TornadoProxyRegistryUpgrade.sol";

import { TornadoProxy, ITornadoInstance } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

import { TornadoTrees } from "tornado-trees/contracts/TornadoTrees.sol";

contract MockProposal is ImmutableGovernanceInformation {
  using SafeMath for uint256;
  using Address for address;

  // ALREADY DEPLOYED
  address public constant tornadoTreesAddress = 0x527653eA119F3E6a1F5BD18fbF4714081D7B31ce;

  // FROM CREATE2 AND NEEDED
  address public constant expectedNewTornadoProxy = 0x1462d01290B2fB36967A10Aa1fc8bB8D9cAe2D31;
  address public constant expectedStaking = 0x749fd724bdd0480dc5830E07e75f4Cd4F4cb2a20;
  RelayerRegistry public constant Registry = RelayerRegistry(0xB6aF8526e71C21c00137a8aE887f91862607a983);

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
    require(expectedNewTornadoProxy.isContract(), "tornado proxy not deployed");
    require(expectedStaking.isContract(), "staking contract not deployed");
    require(address(Registry).isContract(), "registry proxy not deployed");

    LoopbackProxy(returnPayableGovernance()).upgradeTo(
      address(new GovernanceStakingUpgrade(expectedStaking, gasCompLogic, tornadoVault))
    );

    Registry.initialize(GovernanceAddress, expectedStaking, address(tornToken));

    TornadoTrees(tornadoTreesAddress).setTornadoProxyContract(expectedNewTornadoProxy);

    Registry.registerProxy(expectedNewTornadoProxy);

    TornadoProxyRegistryUpgrade TornadoProxy = TornadoProxyRegistryUpgrade(expectedNewTornadoProxy);

    disableOldProxy(TornadoProxy);

    (TornadoProxy.DataManager()).initialize(address(TornadoProxy));

    TornadoProxy.setProtocolFee(1e15);
    TornadoProxy.setPeriodForTWAPOracle(5400);

    Registry.setMinStakeAmount(100 ether);
  }

  function disableOldProxy(TornadoProxyRegistryUpgrade NewTornadoProxy) private {
    TornadoProxy oldProxy = TornadoProxy(oldTornadoProxy);

    TornadoProxy.Tornado memory currentTornado;
    ITornadoInstance currentInstance;
    uint256 bound = NewTornadoProxy.getNumberOfInstances();

    for (uint256 i = 0; i < bound; i++) {
      currentInstance = NewTornadoProxy.getInstanceForPoolId(i);
      (bool isERC20, IERC20 token, ) = oldProxy.instances(currentInstance);
      currentTornado = TornadoProxy.Tornado(
        currentInstance,
        TornadoProxy.Instance(isERC20, token, TornadoProxy.InstanceState.DISABLED)
      );

      oldProxy.updateInstance(currentTornado);
    }
  }
}
