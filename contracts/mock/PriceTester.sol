// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";
import { LowGasSafeMath } from "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";

contract PriceTester {
  using LowGasSafeMath for uint256;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  mapping(address => uint256) public lastPriceOfToken;
  uint256 public lastPriceOfATokenInToken;

  function getPriceOfTokenInToken(
    address[] memory tokens,
    uint24[] memory fees,
    uint32 period
  ) public returns (uint256) {
    lastPriceOfATokenInToken =
      getPriceOfTokenInETH(tokens[0], fees[0], period).mul(1e18) /
      getPriceOfTokenInETH(tokens[1], fees[1], period);
    return lastPriceOfATokenInToken;
  }

  function getPriceOfTokenInETH(
    address token,
    uint24 fee,
    uint32 period
  ) public returns (uint256) {
    lastPriceOfToken[token] = UniswapV3OracleHelper.getPriceOfTokenInToken(token, WETH, fee, period);
    return lastPriceOfToken[token];
  }
}
