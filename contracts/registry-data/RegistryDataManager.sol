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

  PoolData public constant TornTokenData = PoolData(10000, 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);

  function updateRegistryDataArray(PoolData[] memory poolIdToPoolData, GlobalPoolData calldata globalPoolData)
    external
    view
    returns (uint256[] memory newPoolIdToFee)
  {
    for (uint256 i = 0; i < poolIdToPoolData.length; i++) {
      newPoolIdToFee[i].push(
        getBalanceOfPool(poolIdToPoolData.addressData)
          .mul(1e18)
          .div(
            UniswapV3OracleHelper.getPriceRatioOfTokens(
              [TornTokenData.addressData, ERC20Tornado(poolIdToPoolData[i].addressData).token()],
              [uint24(TornTokenData.uniPoolFee), uint24(poolIdToPoolData[i].uniPoolFee)],
              uint32(globalPoolData.globalPeriod)
            )
          )
          .mul(uint256(globalPoolData.protocolFee))
          .div(1e18)
      );
    }
  }

  function getBalanceOfPool(address poolAddress) internal view returns (uint256) {
    return IERC20(ERC20Tornado(poolAddress).token()).balanceOf(poolAddress);
  }
}
