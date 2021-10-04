// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { GovernanceGasUpgrade } from "../../submodules/tornado-lottery-period/contracts/gas/GovernanceGasUpgrade.sol";

interface ITornadoStakingRewards {
  function updateRewardsOnLockedBalanceChange(address account, uint256 amountLockedBeforehand) external;
}

/**
 * @notice The Governance staking upgrade. Adds modifier to any un/lock operation to update rewards
 * @dev CONTRACT RISKS:
 *      - if updateRewards reverts (should not happen due to try/catch) locks/unlocks could be blocked
 *      - generally inherits risks from former governance upgrades
 */
contract GovernanceStakingUpgrade is GovernanceGasUpgrade {
  ITornadoStakingRewards public immutable Staking;

  event RewardUpdateSuccessful(address indexed account);
  event RewardUpdateFailed(address indexed account, bytes indexed errorData);

  constructor(
    address stakingRewardsAddress,
    address gasCompLogic,
    address userVaultAddress
  ) public GovernanceGasUpgrade(gasCompLogic, userVaultAddress) {
    Staking = ITornadoStakingRewards(stakingRewardsAddress);
  }

  /**
   * @notice This modifier should make a call to Staking to update the rewards for account without impacting logic on revert
   * @dev try / catch block to handle reverts
   * @param account Account to update rewards for.
   * */
  modifier updateRewards(address account) {
    try Staking.updateRewardsOnLockedBalanceChange(account, lockedBalance[account]) {
      emit RewardUpdateSuccessful(account);
    } catch (bytes memory errorData) {
      emit RewardUpdateFailed(account, errorData);
    }
    _;
  }

  /// @inheritdoc GovernanceGasUpgrade
  function lock(
    address owner,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override updateRewards(owner) {
    torn.permit(owner, address(this), amount, deadline, v, r, s);
    _transferTokens(owner, amount);
  }

  /// @inheritdoc GovernanceGasUpgrade
  function lockWithApproval(uint256 amount) external virtual override updateRewards(msg.sender) {
    _transferTokens(msg.sender, amount);
  }

  /// @inheritdoc GovernanceGasUpgrade
  function unlock(uint256 amount) external virtual override updateRewards(msg.sender) {
    require(getBlockTimestamp() > canWithdrawAfter[msg.sender], "Governance: tokens are locked");
    lockedBalance[msg.sender] = lockedBalance[msg.sender].sub(amount, "Governance: insufficient balance");
    userVault.withdrawTorn(msg.sender, amount);
  }
}
