// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";

contract PriceTester {
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  mapping(address => uint256) public lastPriceOfToken;

  function getPriceOfTokenInETH(
    address token,
    uint24 fee,
    uint32 period
  ) external returns (uint256) {
    lastPriceOfToken[token] = UniswapV3OracleHelper.getPriceOfTokenInToken(token, WETH, fee, period);
    return lastPriceOfToken[token];
  }
}
