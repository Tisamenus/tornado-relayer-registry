// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";
import { RelayerRegistryData } from "./RelayerRegistryData.sol";
import { SafeMath } from "@openzeppelin/0.6.x/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/0.6.x/token/ERC20/IERC20.sol";

interface ERC20Tornado {
  function token() external view returns (address);
}

struct PoolData {
  uint96 uniPoolFee;
  address addressData;
}

struct GlobalPoolData {
  uint128 protocolFee;
  uint128 globalPeriod;
}

contract RegistryDataManager {
  using SafeMath for uint256;

  // immutable variables need to have a value type, structs can't work
  uint24 public constant uniPoolFeeTorn = 10000;
  address public constant torn = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;
  address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  function updateRegistryDataArray(PoolData[] memory poolIdToPoolData, GlobalPoolData calldata globalPoolData)
    public
    view
    returns (uint256[] memory newPoolIdToFee)
  {
    newPoolIdToFee = new uint256[](newPoolIdToFee.length);
    for (uint256 i = 0; i < poolIdToPoolData.length; i++) {
      newPoolIdToFee[i] = getBalanceOfPool(poolIdToPoolData[i].addressData, i)
        .mul(1e18)
        .div(
          (i > 3)
            ? UniswapV3OracleHelper.getPriceRatioOfTokens(
              [torn, ERC20Tornado(poolIdToPoolData[i].addressData).token()],
              [uniPoolFeeTorn, uint24(poolIdToPoolData[i].uniPoolFee)],
              uint32(globalPoolData.globalPeriod)
            )
            : UniswapV3OracleHelper.getPriceOfWETHInToken(torn, uniPoolFeeTorn, uint32(globalPoolData.globalPeriod))
        )
        .mul(uint256(globalPoolData.protocolFee))
        .div(1e18);
    }
  }

  function getBalanceOfPool(address poolAddress, uint256 isEthIndex) internal view returns (uint256) {
    return (isEthIndex > 3) ? IERC20(ERC20Tornado(poolAddress).token()).balanceOf(poolAddress) : poolAddress.balance;
  }
}
