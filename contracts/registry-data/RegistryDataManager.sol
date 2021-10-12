// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";
import { RelayerRegistryData } from "./RelayerRegistryData.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
  bool[] etherIndices;
}

/// @notice Upgradeable contract which calculates the fee for each pool
/// @dev If you want to modify how staking works update this contract + the registry contract
contract RegistryDataManager {
  using SafeMath for uint256;

  // immutable variables need to have a value type, structs can't work
  uint24 public constant uniPoolFeeTorn = 10000;
  address public constant torn = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;

  /**
   * @notice function to update the entire array of pools
   * @param poolIdToPoolData array of pool data which will be used as input to construct the new array
   * @param globalPoolData data which is independent of each pool
   * @return newPoolIdToFee the new fee array
   */
  function updateRegistryDataArray(PoolData[] memory poolIdToPoolData, GlobalPoolData memory globalPoolData)
    public
    view
    returns (uint256[] memory newPoolIdToFee)
  {
    newPoolIdToFee = new uint256[](poolIdToPoolData.length);
    for (uint256 i = 0; i < poolIdToPoolData.length; i++) {
      newPoolIdToFee[i] = updateSingleRegistryDataArrayElement(poolIdToPoolData[i], globalPoolData, i);
    }
  }

  /**
   * @notice function to update a single fee entry
   * @param poolData data of the pool for which to update fees
   * @param globalPoolData data which is independent of each pool
   * @return newFee the new fee pool
   */
  function updateSingleRegistryDataArrayElement(
    PoolData memory poolData,
    GlobalPoolData memory globalPoolData,
    uint256 isEtherIndex
  ) public view returns (uint256 newFee) {
    if (!globalPoolData.etherIndices[isEtherIndex]) {
      address token = ERC20Tornado(poolData.addressData).token();
      newFee = IERC20(token).balanceOf(poolData.addressData).mul(1e18).div(
        UniswapV3OracleHelper.getPriceRatioOfTokens(
          [torn, token],
          [uniPoolFeeTorn, uint24(poolData.uniPoolFee)],
          uint32(globalPoolData.globalPeriod)
        )
      );
    } else {
      newFee = poolData.addressData.balance.mul(1e18).div(
        UniswapV3OracleHelper.getPriceOfTokenInWETH(torn, uniPoolFeeTorn, uint32(globalPoolData.globalPeriod))
      );
    }
    newFee = newFee.mul(uint256(globalPoolData.protocolFee)).div(1e18);
  }
}
