// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/0.6/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/0.6/math/SafeMath.sol";

import "tornado-lottery-period/contracts/interfaces/ITornadoVault.sol";

interface ITornadoGovernance {
  function userVault() external view returns (ITornadoVault);
}

contract TornadoStakingRewards {
  using SafeMath for uint256;

  IERC20 public immutable torn;
  ITornadoGovernance public immutable Governance;
  uint256 public immutable ratioConstant;

  address public relayerRegistry;
  uint256 public accumulatedRewardPerTorn;

  mapping(address => uint256) public accumulatedOnLastClaim;

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

  function registerRelayerRegistry(address relayerRegistryAddress) external onlyGovernance {
    relayerRegistry = relayerRegistryAddress;
  }

  function addBurnRewards(uint256 amount) external onlyRelayerRegistry {
    accumulatedRewardPerTorn = accumulatedRewardPerTorn.add(
      amount.mul(ratioConstant).div(torn.balanceOf(address(Governance.userVault())))
    );
  }

  function claimFor(
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
    if (amountLockedBeforehand == 0) {
      accumulatedOnLastClaim[account] = accumulatedRewardPerTorn;
      return (0, false);
    }

    claimed = (accumulatedRewardPerTorn.sub(accumulatedOnLastClaim[account])).mul(amountLockedBeforehand).div(ratioConstant);

    accumulatedOnLastClaim[account] = accumulatedRewardPerTorn;

    transferSuccess = torn.transfer(recipient, claimed);
  }
}
