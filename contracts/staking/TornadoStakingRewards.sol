// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";

struct RewardsDurationData {
  uint128 rewardRateChange;
  uint128 endTimestamp;
}

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

  RewardsDurationData[] public rewardsDurationData;
  uint256 public periodIndex;

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
    require(msg.sender == address(governance), "only governance");
    _;
  }

  function addStake(address sender, uint256 tornAmount) external {
    require(TORN.transferFrom(sender, address(this), tornAmount), "tf_fail");
    uint256 oldRewardRate = rewardRate;
    uint256 period = distributionPeriod;
    uint256 dRate = tornAmount.div(period);

    rewardsDurationData.push(RewardsDurationData(uint128(dRate), uint128(block.timestamp.add(period))));

    _updateRewardsState(
      oldRewardRate,
      lastActivityTimestamp,
      totalCollectedShareValue,
      lockedAmount.mul(distributionPeriod),
      periodIndex
    );

    rewardRate = oldRewardRate.add(dRate);
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
    uint256 newTotalCollectedShareValue = _updateRewardsState(
      rewardRate,
      lastActivityTimestamp,
      totalCollectedShareValue,
      lockedAmount.mul(distributionPeriod),
      periodIndex
    );

    claimed = (newTotalCollectedShareValue.sub(collectedAfterAccountInteraction[account])).mul(amountLockedBeforehand).div(
      ratioConstant
    );

    collectedAfterAccountInteraction[account] = newTotalCollectedShareValue;

    transferSuccess = TORN.transfer(recipient, claimed);
  }

  function _updateRewardsState(
    uint256 oldRewardRate,
    uint256 lastTimestamp,
    uint256 newTotalCollectedShareValue,
    uint256 cachedDivisor,
    uint256 cachedPeriodIndex
  ) private returns (uint256) {
    RewardsDurationData memory durationData;

    if (cachedPeriodIndex < rewardsDurationData.length) durationData = rewardsDurationData[cachedPeriodIndex];
    else durationData.endTimestamp = type(uint128).max;

    if (block.timestamp > durationData.endTimestamp) {
      cachedPeriodIndex++;

      newTotalCollectedShareValue = newTotalCollectedShareValue.add(
        oldRewardRate.mul(ratioConstant).mul(uint256(durationData.endTimestamp).sub(lastTimestamp)).div(cachedDivisor)
      );
      lastTimestamp = durationData.endTimestamp;

      oldRewardRate = oldRewardRate.sub(durationData.rewardRateChange);

      if (
        cachedPeriodIndex < rewardsDurationData.length && block.timestamp >= rewardsDurationData[cachedPeriodIndex].endTimestamp
      ) return _updateRewardsState(oldRewardRate, lastTimestamp, newTotalCollectedShareValue, cachedDivisor, cachedPeriodIndex);

      rewardRate = oldRewardRate;
    }

    newTotalCollectedShareValue = newTotalCollectedShareValue.add(
      oldRewardRate.mul(ratioConstant).mul(block.timestamp.sub(lastTimestamp)).div(cachedDivisor)
    );

    totalCollectedShareValue = newTotalCollectedShareValue;
    lastActivityTimestamp = block.timestamp;
    periodIndex = cachedPeriodIndex;

    return newTotalCollectedShareValue;
  }
}
