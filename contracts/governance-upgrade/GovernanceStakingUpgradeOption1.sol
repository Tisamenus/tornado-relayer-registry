// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { GovernanceVaultUpgrade } from "../../submodules/tornado-lottery-period/contracts/vault/GovernanceVaultUpgrade.sol";

interface ITornadoStakingRewards {
  function governanceClaimFor(address recipient, address vault) external;
  function setStakePoints(address staker, uint256 amountLockedBeforehand) external;
}

contract GovernanceStakingUpgradeOption1 is GovernanceVaultUpgrade {
  ITornadoStakingRewards public immutable staking;

  constructor(address stakingRewardsAddress) public {
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
    super.lock(owner, amount.add(claimed), deadline, v, r,s);
  }

  function lockWithApproval(uint256 amount) external virtual override {
    uint256 claimed = staking.governanceClaimFor(msg.sender, address(userVault));
    staking.setStakePoints(msg.sender, lockedBalance[msg.sender]);
    super.lockWithApproval(amount.add(claimed));
  }

  function unlock(uint256 amount) external virtual override {
    staking.governanceClaimFor(msg.sender, msg.sender);
    staking.setStakePoints(msg.sender, lockedBalance[msg.sender]);
    super.unlock(amount);
  }
}