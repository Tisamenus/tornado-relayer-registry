// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { LowGasSafeMath } from "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";

interface IERC20Decimals {
  function decimals() external view returns (uint8);
}

library UniswapV3OracleHelper {
  using LowGasSafeMath for uint256;

  IUniswapV3Factory public constant UniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  function getPriceOfTokenInToken(
    address baseToken,
    address quoteToken,
    uint24 fee,
    uint32 period
  ) public view returns (uint256) {
    return
      OracleLibrary.getQuoteAtTick(
        OracleLibrary.consult(UniswapV3Factory.getPool(baseToken, quoteToken, fee), period),
        uint128(10)**uint128(IERC20Decimals(quoteToken).decimals()),
        baseToken,
        quoteToken
      );
  }

  function getPriceOfTokenInWETH(
    address token,
    uint24 fee,
    uint32 period
  ) public view returns (uint256) {
    return getPriceOfTokenInToken(token, WETH, fee, period);
  }

  function getPriceOfWETHInToken(
    address token,
    uint24 fee,
    uint32 period
  ) public view returns (uint256) {
    return getPriceOfTokenInToken(WETH, token, fee, period);
  }

  function getPriceRatioOfTokens(
    address[2] memory tokens,
    uint24[2] memory fees,
    uint32 period
  ) public view returns (uint256) {
    return getPriceOfTokenInWETH(tokens[0], fees[0], period).mul(1e18) / getPriceOfTokenInWETH(tokens[1], fees[1], period);
  }
}
