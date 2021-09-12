// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

interface IERC20Decimals {
  function decimals() external returns (uint8);
}

library UniswapV3OracleHelper {
  IUniswapV3Factory public constant UniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

  function getPriceOfTokenInToken(
    address baseToken,
    address quoteToken,
    uint24 fee,
    uint32 period
  ) public returns (uint256) {
    return
      OracleLibrary.getQuoteAtTick(
        OracleLibrary.consult(UniswapV3Factory.getPool(baseToken, quoteToken, fee), period),
        uint128(10)**uint128(IERC20Decimals(baseToken).decimals()),
        baseToken,
        quoteToken
      );
  }
}
