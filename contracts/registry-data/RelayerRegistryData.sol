// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RegistryDataManager, PoolData, GlobalPoolData } from "./RegistryDataManager.sol";

/// @notice Contract which holds important data related to each tornado instance
contract RelayerRegistryData {
  address public immutable governance;
  RegistryDataManager public immutable DataManager;

  PoolData[] public getPoolDataForPoolId;
  uint256[] public getFeeForPoolId;

  mapping(address => uint256) public getPoolIdForAddress;

  GlobalPoolData public dataForTWAPOracle;

  event FeesUpdated(uint256 indexed timestamp);
  event FeeUpdated(uint256 indexed timestamp, uint256 indexed poolId);

  constructor(
    address dataManagerProxy,
    address tornadoGovernance,
    uint96[] memory initPoolDataFees,
    address[] memory initPoolDataAddresses
  ) public {
    DataManager = RegistryDataManager(dataManagerProxy);
    governance = tornadoGovernance;

    for (uint256 i = 0; i < initPoolDataFees.length; i++) {
      getPoolDataForPoolId.push(PoolData(initPoolDataFees[i], initPoolDataAddresses[i]));
      getPoolIdForAddress[initPoolDataAddresses[i]] = getPoolDataForPoolId.length - 1;
    }

    bool[] storage indexes = dataForTWAPOracle.etherIndices;

    for (uint256 i = 0; i < initPoolDataFees.length; i++) {
      if (i < 4) indexes.push(true);
      else indexes.push(false);
    }
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, "only governance");
    _;
  }

  /**
   * @notice This function should update the fees for poolIds tornado instances
   *         (here called pools)
   * @param poolIds poolIds to update fees for
   * */
  function updateFeesOfPools(uint256[] memory poolIds) external {
    for (uint256 i = 0; i < poolIds.length; i++) {
      updateFeeOfPool(poolIds[i]);
    }
  }

  /**
   * @notice This function should allow governance to register a new tornado erc20 instance
   * @param uniPoolFee fee of the uniswap pool used to get prices
   * @param poolAddress address of the instance
   * @return poolId id of the pool
   * */
  function addPool(uint96 uniPoolFee, address poolAddress) external onlyGovernance returns (uint256 poolId) {
    poolId = _addPool(uniPoolFee, poolAddress);
    dataForTWAPOracle.etherIndices.push(false);
  }

  /**
   * @notice This function should allow governance to register a new tornado eth instance
   * @param uniPoolFee fee of the uniswap pool used to get prices (here irrelevant!)
   * @param poolAddress address of the instance
   * @return poolId id of the pool
   * */
  function addEtherPool(uint96 uniPoolFee, address poolAddress) external onlyGovernance returns (uint256 poolId) {
    poolId = _addPool(uniPoolFee, poolAddress);
    dataForTWAPOracle.etherIndices.push(true);
  }

  /**
   * @notice This function should allow governance to set the new protocol fee for relayers
   * @param newFee the new fee to use
   * */
  function setProtocolFee(uint128 newFee) external onlyGovernance {
    dataForTWAPOracle.protocolFee = newFee;
  }

  /**
   * @notice This function should allow governance to set the new period for twap measurement
   * @param newPeriod the new period to use
   * */
  function setPeriodForTWAPOracle(uint128 newPeriod) external onlyGovernance {
    dataForTWAPOracle.globalPeriod = newPeriod;
  }

  /**
   * @notice This function should get the fee for the pool address in one go
   * @dev getFeeForPoolId is an array to so we can iterate it to update prices
   * @param pool address of the tornado instance
   * @return fee for the pool
   * */
  function getFeeForPoolAddress(address pool) external view returns (uint256) {
    return getFeeForPoolId[getPoolIdForAddress[pool]];
  }

  /**
   * @notice This function should update the fees of each pool
   */
  function updateAllFees() public {
    getFeeForPoolId = DataManager.updateRegistryDataArray(getPoolDataForPoolId, dataForTWAPOracle);
    emit FeesUpdated(block.timestamp);
  }

  /**
   * @notice This function should update the fee of a specific pool
   * @param poolId id of the pool to update fees for
   */
  function updateFeeOfPool(uint256 poolId) public {
    getFeeForPoolId[poolId] = DataManager.updateSingleRegistryDataArrayElement(
      getPoolDataForPoolId[poolId],
      dataForTWAPOracle,
      poolId
    );
    emit FeeUpdated(block.timestamp, poolId);
  }

  /**
   * @notice internal function to add a pool
   * @param uniPoolFee fee of the uniswap pool used to get prices (here irrelevant!)
   * @param poolAddress address of the instance
   */
  function _addPool(uint96 uniPoolFee, address poolAddress) internal returns (uint256) {
    getPoolDataForPoolId.push(PoolData(uniPoolFee, poolAddress));
    getPoolIdForAddress[poolAddress] = getPoolDataForPoolId.length - 1;
    getFeeForPoolId.push(0);
    return getPoolDataForPoolId.length - 1;
  }
}
