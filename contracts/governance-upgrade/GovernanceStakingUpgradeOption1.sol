// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { GovernanceVaultUpgrade } from "../../submodules/tornado-lottery-period/contracts/vault/GovernanceVaultUpgrade.sol";

interface ITornadoStakingRewards {
  function governanceClaimFor(address recipient, address vault) external returns (uint256);

  function setStakePoints(address staker, uint256 amountLockedBeforehand) external;

  function setStakedAmountOnLock(uint256 amount) external;

  function setStakedAmountOnUnlock(uint256 amount) external;
}

contract GovernanceStakingUpgradeOption1 is GovernanceVaultUpgrade {
  ITornadoStakingRewards public immutable staking;

  constructor(address stakingRewardsAddress, address userVaultAddress) public GovernanceVaultUpgrade(userVaultAddress) {
    staking = ITornadoStakingRewards(stakingRewardsAddress);
  }

  function lock(
    address owner,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override {
    uint256 claimed = staking.governanceClaimFor(owner, address(userVault));
    staking.setStakePoints(owner, lockedBalance[owner]);

    torn.permit(owner, address(this), amount, deadline, v, r, s);
    _transferTokens(owner, amount);

    lockedBalance[owner] += claimed;
    staking.setStakedAmountOnLock(amount.add(claimed));
  }

  function lockWithApproval(uint256 amount) external virtual override {
    uint256 claimed = staking.governanceClaimFor(msg.sender, address(userVault));
    staking.setStakePoints(msg.sender, lockedBalance[msg.sender]);

    _transferTokens(msg.sender, amount);

    lockedBalance[msg.sender] += claimed;
    staking.setStakedAmountOnLock(amount.add(claimed));
  }

  function unlock(uint256 amount) external virtual override {
    staking.governanceClaimFor(msg.sender, msg.sender);
    staking.setStakePoints(msg.sender, lockedBalance[msg.sender]);

    require(getBlockTimestamp() > canWithdrawAfter[msg.sender], "Governance: tokens are locked");
    lockedBalance[msg.sender] = lockedBalance[msg.sender].sub(amount, "Governance: insufficient balance");
    require(torn.transfer(msg.sender, amount), "TORN: transfer failed");

    staking.setStakedAmountOnUnlock(amount);
  }
}
