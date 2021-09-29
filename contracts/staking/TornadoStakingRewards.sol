// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";

contract TornadoStakingRewards {
  using SafeMath for uint256;

  address public immutable governance;

  IERC20 public immutable torn;
  uint256 public immutable ratioConstant;

  address public relayerRegistry;
  uint256 public totalCollectedShareValue;
  uint256 public lockedAmount;

  mapping(address => uint256) public collectedAfterAccountInteraction;

  constructor(
    address governanceAddress,
    address tornAddress,
    uint256 initialLockedAmount
  ) public {
    governance = governanceAddress;
    torn = IERC20(tornAddress);
    ratioConstant = IERC20(tornAddress).totalSupply();
    lockedAmount = initialLockedAmount;
  }

  modifier onlyGovernance() {
    require(msg.sender == address(governance), "only governance");
    _;
  }

  modifier onlyRelayerRegistry() {
    require(msg.sender == address(relayerRegistry), "only tornado proxy");
    _;
  }

  function addBurnRewards(uint256 amount) external onlyRelayerRegistry {
    totalCollectedShareValue = totalCollectedShareValue.add(amount.mul(ratioConstant).div(lockedAmount));
  }

  function registerRelayerRegistry(address registryAddress) external onlyGovernance {
    relayerRegistry = registryAddress;
  }

  function updateLockedAmountOnLock(uint256 amount) external onlyGovernance {
    lockedAmount = lockedAmount.add(amount);
  }

  function updateLockedAmountOnUnlock(uint256 amount) external onlyGovernance {
    lockedAmount = lockedAmount.sub(amount);
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
    claimed = (totalCollectedShareValue.sub(collectedAfterAccountInteraction[account])).mul(amountLockedBeforehand).div(
      ratioConstant
    );

    collectedAfterAccountInteraction[account] = totalCollectedShareValue;

    transferSuccess = torn.transfer(recipient, claimed);
  }
}
