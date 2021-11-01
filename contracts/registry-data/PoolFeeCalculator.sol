// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";

import "tornado-anonymity-mining/contracts/interfaces/ITornadoInstance.sol";
import "../tornado-proxy/ModifiedTornadoProxy.sol";

interface ITornadoProxy {
  function getPoolToken(ITornadoInstance instance) external view returns (address);
}

struct PoolData {
  uint96 uniswapPoolSwappingFee;
  uint160 tornFeeOfPool;
}

struct ProxyPoolParameters {
  uint128 proxyFee;
  uint128 uniswapTimePeriod;
}

/// @notice Upgradeable contract which calculates the fee for each pool, this is not a library due to upgradeability
/// @dev If you want to modify how staking works update this contract + the registry contract
contract PoolFeeCalculator is Initializable {
  using SafeMath for uint256;

  // immutable variables need to have a value type, structs can't work
  uint24 public constant uniswapTornPoolSwappingFee = 10000;
  address public constant torn = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;

  ITornadoProxy public TornadoProxy;

  function initialize(address tornadoProxy) external initializer {
    TornadoProxy = ITornadoProxy(tornadoProxy);
  }

  /**
   * @notice function to update a single fee entry
   * @param instance instance for which to update data
   * @param instanceData data associated with the instance
   * @param proxyPoolParameters data which is independent of each pool
   * @return newFee the new fee pool
   */
  function updateSingleRegistryPoolFee(
    ITornadoInstance instance,
    ModifiedTornadoProxy.Instance calldata instanceData,
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
