// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";

import "tornado-anonymity-mining/contracts/interfaces/ITornadoInstance.sol";
import "../tornado-proxy/TornadoProxyWithPoolData.sol";

interface ITornadoProxy {
  function getPoolToken(ITornadoInstance instance) external view returns (address);
}

/// @dev data attributed to a single tornado pool, which is not already stored
///      in the tornado proxy. uniswapPoolSwappingFee is the fee of the uniswap pool
///      which will be used to get a TWAP, and tornFeeOfPool is the fee relayers have to pay
///      when withdrawing for someone from the pool
struct PoolData {
  uint96 uniswapPoolSwappingFee;
  uint160 tornFeeOfPool;
}

/// @dev data attributed to all tornado pools, proxyFee is the fee constant used to
///      calculate tornFeeOfPool for each pool and uniswapTimePeriod is the lookback
///      in seconds for each pool (for simplicity)
struct ProxyPoolParameters {
  uint128 proxyFee;
  uint128 uniswapTimePeriod;
}

/// @notice Upgradeable contract which calculates the fee for each pool, this is not a library due to upgradeability
/// @dev If you want to modify how staking works update this contract + the registry contract
contract PoolFeeCalculator {
  using SafeMath for uint256;

  // immutable variables need to have a value type, structs can't work
  uint24 public constant uniswapTornPoolSwappingFee = 10000;
  address public constant torn = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;

  /**
   * @notice function to update a single fee entry
   * @param instance instance for which to update data
   * @param instanceData data associated with the instance
   * @param proxyPoolParameters data which is independent of each pool
   * @return newFee the new fee pool
   */
  function calculateSingleRegistryPoolFee(
    ITornadoInstance instance,
    TornadoProxyWithPoolData.Instance calldata instanceData,
    ProxyPoolParameters memory proxyPoolParameters
  ) public view returns (uint160 newFee) {
    return
      uint160(
        instance
          .denomination()
          .mul(1e18)
          .div(
            UniswapV3OracleHelper.getPriceRatioOfTokens(
              [torn, address(instanceData.token)],
              [uniswapTornPoolSwappingFee, uint24(instanceData.poolData.uniswapPoolSwappingFee)],
              uint32(proxyPoolParameters.uniswapTimePeriod)
            )
          )
          .mul(uint256(proxyPoolParameters.proxyFee))
          .div(1e18)
      );
  }
}
