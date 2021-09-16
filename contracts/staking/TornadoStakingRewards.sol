// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";

struct TornadoStakerData {
  uint128 stakePoints;
  uint128 timestampLastAction;
}

contract TornadoStakingRewards {
  using SafeMath for uint256;
  using SafeMath for uint128;

  address public immutable governance;
  uint256 public immutable ratioConstant;
  IERC20 public immutable torn;

  uint256 public currentSharePrice;
  uint256 public distributionPeriod;
  uint256 public stakedAmount;

  mapping(address => TornadoStakerData) public getStakerDataForStaker;

  constructor(
    address governanceAddress,
    address tornAddress,
    uint256 initialStakedAmount
  ) public {
    governance = governanceAddress;
    torn = IERC20(tornAddress);
    ratioConstant = IERC20(tornAddress).totalSupply();
    stakedAmount = initialStakedAmount;
  }

  modifier onlyGovernance() {
    require(msg.sender == address(governance));
    _;
  }

  function addStake(address sender, uint256 tornAmount) external {
    require(torn.transferFrom(sender, address(this), tornAmount), "tf_fail");
    currentSharePrice = currentSharePrice.add(tornAmount.mul(ratioConstant).div(stakedAmount).div(distributionPeriod));
  }

  function claim() external returns (uint256) {
    return _consumeStakePoints(msg.sender, msg.sender);
  }

  function governanceClaimFor(address recipient, address vault) external onlyGovernance {
    stakedAmount += _consumeStakePoints(recipient, vault);
  }

  function setDistributionPeriod(uint256 period) external onlyGovernance {
    distributionPeriod = period;
  }

  function setStakePoints(address staker, uint256 amountLockedBeforehand) external onlyGovernance {
    getStakerDataForStaker[staker] = TornadoStakerData(
      uint128(
        uint256(getStakerDataForStaker[staker].stakePoints).add(
          amountLockedBeforehand.mul(block.timestamp.sub(getStakerDataForStaker[staker].timestampLastAction))
        )
      ),
      uint128(block.timestamp)
    );
  }

  function _consumeStakePoints(address recipient, address staker) private returns (uint256 claimed) {
    claimed = uint256(getStakerDataForStaker[staker].stakePoints).mul(currentSharePrice).div(ratioConstant);
    require(torn.transfer(recipient, claimed));
    getStakerDataForStaker[staker].stakePoints = 0;
  }
}
