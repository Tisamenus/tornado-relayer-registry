// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RelayerRegistryData } from "./registry-data/RelayerRegistryData.sol";
import { EnsResolve } from "./interfaces/EnsResolve.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";

struct RelayerMetadata {
  uint256 fee;
}

contract RelayerRegistry is EnsResolve {
  using SafeMath for uint256;

  address public immutable Governance;
  address public immutable tornadoProxy;

  IERC20 public immutable torn;

  RelayerRegistryData public immutable RegistryData;

  uint256 public minStakeAmount;

  mapping(bytes32 => uint256) getBalanceForRelayer;

  constructor(
    address registryDataAddress,
    address tornadoGovernance,
    address tornAddress,
    address tornadoProxyAddress
  ) public {
    RegistryData = RelayerRegistryData(registryDataAddress);
    Governance = tornadoGovernance;
    torn = IERC20(tornAddress);
    tornadoProxy = tornadoProxyAddress;
  }

  modifier onlyGovernance() {
    require(msg.sender == Governance);
    _;
  }

  modifier onlyTornadoProxy() {
    require(msg.sender == tornadoProxy);
    _;
  }

  function stakeToRelayer(bytes32 relayer, uint256 stake) external {
    require(stake.add(getBalanceForRelayer[relayer]) >= minStakeAmount, "min_stake");
    require(torn.transferFrom(resolve(relayer), Governance, stake), "transfer");
    getBalanceForRelayer[relayer] += stake;
  }

  function setMinStakeAmount(uint256 minAmount) external onlyGovernance {
    minStakeAmount = minAmount;
  }

  function burn(bytes32 relayer, address poolAddress) external onlyTornadoProxy {
    getBalanceForRelayer[relayer] = getBalanceForRelayer[relayer].sub(
      RegistryData.getFeeForPoolId(RegistryData.getPoolIdForAddress(poolAddress))
    );
  }
}
