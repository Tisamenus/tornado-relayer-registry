// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "tornado-lottery-period/contracts/interfaces/ITornadoVault.sol";

interface ITornadoGovernance {
  function lockedBalance(address account) external view returns (uint256);

  function userVault() external view returns (ITornadoVault);
}

contract TornadoStakingRewards is ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  ITornadoGovernance public immutable Governance;
  IERC20 public immutable torn;

  uint256 public immutable ratioConstant;

  address public relayerRegistry;
  uint256 public accumulatedRewardPerTorn;

  mapping(address => uint256) public accumulatedRewardRateOnLastUpdate;
  mapping(address => uint256) public accumulatedRewards;

  event RewardsUpdated(address indexed account, uint256 indexed rewards);
  event RewardsClaimed(address indexed account, uint256 indexed rewardsClaimed);
  event AccumulatedRewardPerTornUpdated(uint256 indexed newRewardPerTorn);

  constructor(address governanceAddress, address tornAddress) public {
    Governance = ITornadoGovernance(governanceAddress);
    torn = IERC20(tornAddress);
    ratioConstant = IERC20(tornAddress).totalSupply();
  }

  modifier onlyGovernance() {
    require(msg.sender == address(Governance), "only governance");
    _;
  }

  modifier onlyRelayerRegistry() {
    require(msg.sender == relayerRegistry, "only relayer registry");
    _;
  }

  /**
   * @dev We know that rewards are going to be updated every time someone locks or unlocks
   * so we know that this function can't be used to falsely increase the amount of lockedTorn by locking in governance
   * and subsequently calling it.
   */
  function getReward() external nonReentrant {
    uint256 rewards = _updateReward(msg.sender, Governance.lockedBalance(msg.sender));
    rewards = rewards.add(accumulatedRewards[msg.sender]);
    accumulatedRewards[msg.sender] = 0;
    torn.safeTransfer(msg.sender, rewards);
    emit RewardsClaimed(msg.sender, rewards);
  }

  function registerRelayerRegistry(address relayerRegistryAddress) external onlyGovernance {
    relayerRegistry = relayerRegistryAddress;
  }

  function addBurnRewards(uint256 amount) external onlyRelayerRegistry {
    accumulatedRewardPerTorn = accumulatedRewardPerTorn.add(
      amount.mul(ratioConstant).div(torn.balanceOf(address(Governance.userVault())))
    );
    emit AccumulatedRewardPerTornUpdated(accumulatedRewardPerTorn);
  }

  function updateRewardsOnLockedBalanceChange(address account, uint256 amountLockedBeforehand) external onlyGovernance {
    uint256 claimed = _updateReward(account, amountLockedBeforehand);
    accumulatedRewards[account] = accumulatedRewards[account].add(claimed);
  }

  function _updateReward(address account, uint256 amountLockedBeforehand) private returns (uint256 claimed) {
    claimed = (accumulatedRewardPerTorn.sub(accumulatedRewardRateOnLastUpdate[account])).mul(amountLockedBeforehand).div(
      ratioConstant
    );
    accumulatedRewardRateOnLastUpdate[account] = accumulatedRewardPerTorn;
    emit RewardsUpdated(account, claimed);
  }
}
