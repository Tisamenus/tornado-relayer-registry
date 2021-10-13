// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { UniswapV3OracleHelper } from "../libraries/UniswapV3OracleHelper.sol";
import { RelayerRegistryData } from "./RelayerRegistryData.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";

import { ITornadoInstance } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

interface ITornadoProxy {
  function getPoolToken(ITornadoInstance instance) external view returns (address);
}

struct PoolData {
  uint96 uniPoolFee;
  uint160 protocolPoolFee;
}

struct GlobalPoolData {
  uint128 protocolFee;
  uint128 globalPeriod;
}

/// @notice Upgradeable contract which calculates the fee for each pool, this is not a library due to upgradeability
/// @dev If you want to modify how staking works update this contract + the registry contract
contract RegistryDataManager is Initializable {
  using SafeMath for uint256;

  // immutable variables need to have a value type, structs can't work
  uint24 public constant uniPoolFeeTorn = 10000;
  address public constant torn = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C;

  ITornadoProxy public TornadoProxy;

  function initialize(address tornadoProxy) external initializer {
    TornadoProxy = ITornadoProxy(tornadoProxy);
  }

  /**
   * @notice function to update a single fee entry
   * @param poolData data of the pool for which to update fees
   * @param instance instance for which to update data
   * @param globalPoolData data which is independent of each pool
   * @return newFee the new fee pool
   */
  function updateSingleRegistryPoolFee(
    PoolData memory poolData,
    ITornadoInstance instance,
    GlobalPoolData memory globalPoolData
  ) public view returns (uint160 newFee) {
    return
      uint160(
        instance
          .denomination()
          .mul(1e18)
          .div(
            UniswapV3OracleHelper.getPriceRatioOfTokens(
              [torn, TornadoProxy.getPoolToken(instance)],
              [uniPoolFeeTorn, uint24(poolData.uniPoolFee)],
              uint32(globalPoolData.globalPeriod)
            )
          )
          .mul(uint256(globalPoolData.protocolFee))
          .div(1e18)
      );
  }
}
