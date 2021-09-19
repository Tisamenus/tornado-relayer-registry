// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { GovernanceVaultUpgrade } from "../../submodules/tornado-lottery-period/contracts/vault/GovernanceVaultUpgrade.sol";

interface ITornadoStakingRewards {
  function governanceClaimFor(
    address recipient,
    address vault,
    uint256 amountLockedBeforehand
  ) external returns (uint256);

  function setStakePoints(address staker, uint256 amountLockedBeforehand) external;

  function rebaseSharePriceOnLock(uint256 amount) external;

  function rebaseSharePriceOnUnlock(uint256 amount) external;
}

contract GovernanceStakingUpgradeOption1 is GovernanceVaultUpgrade {
  ITornadoStakingRewards public immutable Staking;

  constructor(address stakingRewardsAddress, address userVaultAddress) public GovernanceVaultUpgrade(userVaultAddress) {
    Staking = ITornadoStakingRewards(stakingRewardsAddress);
  }

  function lock(
    address owner,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override {
    uint256 claimed = Staking.governanceClaimFor(owner, address(userVault), lockedBalance[owner]);

    torn.permit(owner, address(this), amount, deadline, v, r, s);
    _transferTokens(owner, amount);

    lockedBalance[owner] += claimed;
    Staking.rebaseSharePriceOnLock(amount.add(claimed));
  }

  function lockWithApproval(uint256 amount) external virtual override {
    uint256 claimed = Staking.governanceClaimFor(msg.sender, address(userVault), lockedBalance[msg.sender]);

    _transferTokens(msg.sender, amount);

    lockedBalance[msg.sender] += claimed;
    Staking.rebaseSharePriceOnLock(amount.add(claimed));
  }

  function unlock(uint256 amount) external virtual override {
    Staking.governanceClaimFor(msg.sender, msg.sender, lockedBalance[msg.sender]);

    require(getBlockTimestamp() > canWithdrawAfter[msg.sender], "Governance: tokens are locked");
    lockedBalance[msg.sender] = lockedBalance[msg.sender].sub(amount, "Governance: insufficient balance");
    userVault.withdrawTorn(msg.sender, amount);

    Staking.rebaseSharePriceOnUnlock(amount);
  }
}
