// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { GovernanceGasUpgrade } from "../../submodules/tornado-lottery-period/contracts/gas/GovernanceGasUpgrade.sol";

interface ITornadoStakingRewards {
  function governanceClaimFor(
    address staker,
    address recipient,
    uint256 amountLockedBeforehand
  ) external returns (uint256, bool);

  function setStakePoints(address staker, uint256 amountLockedBeforehand) external;

  function rebaseSharePriceOnLock(uint256 amount) external;

  function rebaseSharePriceOnUnlock(uint256 amount) external;
}

interface IRelayerRegistryData {
  function lastFeeUpdateTimestamp() external view returns (uint256);

  function updateAllFeesWithTimestampStore() external;
}

contract GovernanceStakingUpgrade is GovernanceGasUpgrade {
  ITornadoStakingRewards public immutable Staking;
  IRelayerRegistryData public immutable RegistryData;

  constructor(
    address stakingRewardsAddress,
    address registryDataAddress,
    address gasCompLogic,
    address userVaultAddress
  ) public GovernanceGasUpgrade(gasCompLogic, userVaultAddress) {
    Staking = ITornadoStakingRewards(stakingRewardsAddress);
    RegistryData = IRelayerRegistryData(registryDataAddress);
  }

  function updateAllFees()
    external
    gasCompensation(msg.sender, RegistryData.lastFeeUpdateTimestamp() + 6 hours <= block.timestamp, 21e3)
  {
    RegistryData.updateAllFeesWithTimestampStore();
  }

  function lock(
    address owner,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual override {
    (uint256 claimed, bool success) = Staking.governanceClaimFor(owner, address(userVault), lockedBalance[owner]);
    if (!success) claimed = 0;

    torn.permit(owner, address(this), amount, deadline, v, r, s);
    _transferTokens(owner, amount);

    lockedBalance[owner] = lockedBalance[owner].add(claimed);
    Staking.rebaseSharePriceOnLock(amount.add(claimed));
  }

  function lockWithApproval(uint256 amount) external virtual override {
    (uint256 claimed, bool success) = Staking.governanceClaimFor(msg.sender, address(userVault), lockedBalance[msg.sender]);
    if (!success) claimed = 0;

    _transferTokens(msg.sender, amount);

    lockedBalance[msg.sender] = lockedBalance[msg.sender].add(claimed);
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
