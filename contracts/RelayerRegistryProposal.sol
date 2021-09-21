// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { ImmutableGovernanceInformation } from "../submodules/tornado-lottery-period/contracts/ImmutableGovernanceInformation.sol";
import { TornadoVault } from "../submodules/tornado-lottery-period/contracts/vault/TornadoVault.sol";
import { IGovernanceVesting } from "../submodules/tornado-lottery-period/contracts/interfaces/IGovernanceVesting.sol";
import { TornadoAuctionHandler } from "../submodules/tornado-lottery-period/contracts/auction/TornadoAuctionHandler.sol";

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { LoopbackProxy } from "tornado-governance/contracts/LoopbackProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { GovernanceStakingUpgrade } from "./governance-upgrade/GovernanceStakingUpgrade.sol";
import { TornadoStakingRewards } from "./staking/TornadoStakingRewards.sol";
import { RelayerRegistry } from "./RelayerRegistry.sol";
import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { TornadoInstancesData } from "./tornado-proxy/TornadoInstancesData.sol";

import { TornadoProxy } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

contract RelayerRegistryProposal is ImmutableGovernanceInformation {
  using SafeMath for uint256;

  address public constant GovernanceVesting = 0x179f48C78f57A3A78f0608cC9197B8972921d1D2;
  IERC20 public constant tornToken = IERC20(TornTokenAddress);

  RelayerRegistry public immutable Registry;
  TornadoStakingRewards public immutable Staking;
  TornadoInstancesData public immutable InstancesData;

  address public immutable oldTornadoProxy;
  address public immutable newTornadoProxy;
  address public immutable gasCompLogic;

  constructor(
    address relayerRegistryAddress,
    address oldTornadoProxyAddress,
    address newTornadoProxyAddress,
    address stakingAddress,
    address tornadoInstancesDataAddress,
    address gasCompLogicAddress
  ) public {
    Registry = RelayerRegistry(relayerRegistryAddress);
    newTornadoProxy = newTornadoProxyAddress;
    oldTornadoProxy = oldTornadoProxyAddress;
    Staking = TornadoStakingRewards(stakingAddress);
    InstancesData = TornadoInstancesData(tornadoInstancesDataAddress);
    gasCompLogic = gasCompLogicAddress;
  }

  function executeProposal() external {
    /**
    The below variable holds the total amount of TORN outflows from all of the proposal executions,
    which will be used to calculate the proper amount of TORN for transfer to Governance.
    For an explanation as to how this variable has been calculated with these fix values, please look at:
    https://github.com/h-ivor/tornado-lottery-period/blob/final_with_auction/scripts/balance_estimation.md
    */
    uint256 totalOutflowsOfProposalExecutions = 120000000000000000000000 +
      22916666666666666666666 +
      54999999999999969408000 -
      27e18;

    uint256 lockedTokenBalancesInGovernance = IGovernanceVesting(GovernanceVesting).released().sub(
      totalOutflowsOfProposalExecutions
    );

    address vault = address(new TornadoVault());

    LoopbackProxy(returnPayableGovernance()).upgradeTo(
      address(new GovernanceStakingUpgrade(address(Staking), gasCompLogic, vault))
    );

    GovernanceStakingUpgrade newGovernance = GovernanceStakingUpgrade(returnPayableGovernance());

    Registry.registerProxy(newTornadoProxy);

    RelayerRegistryData RegistryData = Registry.RegistryData();

    RegistryData.setProtocolFee(1e15);
    RegistryData.setProtocolPeriod(5400);

    Staking.setDistributionPeriod(365 days);

    Registry.setMinStakeAmount(1e20);

    require(disableOldProxy());

    require(
      tornToken.transfer(
        address(newGovernance.userVault()),
        (tornToken.balanceOf(address(this))).sub(lockedTokenBalancesInGovernance)
      ),
      "TORN: transfer failed"
    );

    uint256 amountOfTornToAuctionOff = 100 ether;

    TornadoAuctionHandler auctionHandler = new TornadoAuctionHandler();
    tornToken.transfer(address(auctionHandler), amountOfTornToAuctionOff);

    /**
    As with above, please see:
    https://github.com/h-ivor/tornado-lottery-period/blob/final_with_auction/contracts/auction/Auction.md
    */
    auctionHandler.initializeAuction(block.timestamp + 5 days, amountOfTornToAuctionOff, 151e16, 1 ether, 0);
  }

  function disableOldProxy() private returns (bool) {
    TornadoProxy oldProxy = TornadoProxy(oldTornadoProxy);
    TornadoProxy.Tornado[] memory Instances = InstancesData.getInstances();

    for (uint256 i = 0; i < Instances.length; i++) {
      oldProxy.updateInstance(Instances[i]);
    }

    return true;
  }
}
