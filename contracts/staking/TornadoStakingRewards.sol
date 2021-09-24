// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";

contract TornadoStakingRewards {
  using SafeMath for uint256;

  address public immutable governance;
  uint256 public immutable ratioConstant;
  IERC20 public immutable TORN;

  uint256 public totalCollectedShareValue;
  uint256 public lastActivityTimestamp;
  uint256 public rewardRate;
  uint256 public lockedAmount;
  uint256 public distributionPeriod;

  mapping(address => uint256) public collectedAfterAccountInteraction;

  constructor(
    address governanceAddress,
    address tornAddress,
    uint256 initialLockedAmount
  ) public {
    governance = governanceAddress;
    TORN = IERC20(tornAddress);
    ratioConstant = IERC20(tornAddress).totalSupply();
    lockedAmount = initialLockedAmount;
  }

  modifier onlyGovernance() {
    require(msg.sender == address(governance));
    _;
  }

  function addStake(address sender, uint256 tornAmount) external {
    require(TORN.transferFrom(sender, address(this), tornAmount), "tf_fail");
    // will throw if block.timestamp - startTime > distributionPeriod
    uint256 oldRewardRate = rewardRate;
    _updateRewardsState(oldRewardRate);
    rewardRate = oldRewardRate.add(tornAmount.div(distributionPeriod));
  }

  function updateLockedAmountOnLock(uint256 amount) external onlyGovernance {
    lockedAmount = lockedAmount.add(amount);
  }

  function updateLockedAmountOnUnlock(uint256 amount) external onlyGovernance {
    lockedAmount = lockedAmount.sub(amount);
  }

  function setDistributionPeriod(uint256 period) external onlyGovernance {
    distributionPeriod = period;
  }

  function governanceClaimFor(
    address account,
    address recipient,
    uint256 amountLockedBeforehand
  ) external onlyGovernance returns (uint256, bool) {
    return _calculateAndPayReward(account, recipient, amountLockedBeforehand);
  }

  function _calculateAndPayReward(
    address account,
    address recipient,
    uint256 amountLockedBeforehand
  ) private returns (uint256 claimed, bool transferSuccess) {
    uint256 newTotalCollectedShareValue = _updateRewardsState(rewardRate);

    claimed = (newTotalCollectedShareValue.sub(collectedAfterAccountInteraction[account])).mul(amountLockedBeforehand).div(
      ratioConstant
    );

    collectedAfterAccountInteraction[account] = newTotalCollectedShareValue;

    transferSuccess = TORN.transfer(recipient, claimed);
  }

  function _updateRewardsState(uint256 oldRewardRate) private returns (uint256) {
    uint256 newTotalCollectedShareValue = totalCollectedShareValue.add(
      oldRewardRate.mul(ratioConstant).mul(block.timestamp.sub(lastActivityTimestamp)).div(lockedAmount).div(distributionPeriod)
    );
    totalCollectedShareValue = newTotalCollectedShareValue;
    lastActivityTimestamp = block.timestamp;
    return newTotalCollectedShareValue;
  }
}
