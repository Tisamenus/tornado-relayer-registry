// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RegistryDataManager, PoolData, GlobalPoolData } from "./RegistryDataManager.sol";

import { ITornadoInstance } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

/// @notice Contract which holds important data related to each tornado instance
contract RelayerRegistryData {
  address public immutable governance;
  address public immutable registry;

  mapping(ITornadoInstance => PoolData) public getPoolDataForInstance;
  ITornadoInstance[] public getInstanceForPoolId;

  GlobalPoolData public dataForTWAPOracle;
  RegistryDataManager public DataManager;

  event FeesUpdated(uint256 indexed timestamp);
  event FeeUpdated(uint256 indexed timestamp, uint256 indexed poolId);

  constructor(
    address dataManagerProxy,
    address relayerRegistryAddress,
    address tornadoGovernance,
    address[] memory initPoolDataAddresses,
    uint96[] memory initUniPoolFees,
    uint160[] memory initProtocolPoolFees
  ) public {
    DataManager = RegistryDataManager(dataManagerProxy);
    governance = tornadoGovernance;
    registry = relayerRegistryAddress;

    for (uint256 i = 0; i < initUniPoolFees.length; i++) {
      getPoolDataForInstance[ITornadoInstance(initPoolDataAddresses[i])] = PoolData(initUniPoolFees[i], initProtocolPoolFees[i]);
      getInstanceForPoolId.push(ITornadoInstance(initPoolDataAddresses[i]));
    }
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, "only governance");
    _;
  }

  modifier onlyRelayerRegistry() {
    require(msg.sender == registry, "only registry");
    _;
  }

  /**
   * @notice This function should update the fees for poolIds tornado instances
   *         (here called pools)
   * @param poolIds poolIds to update fees for
   * */
  function updateFeesOfPools(uint256[] memory poolIds) public {
    for (uint256 i = 0; i < poolIds.length; i++) {
      updateFeeOfPool(poolIds[i]);
    }
  }

  /**
   * @notice This function should allow governance to register a new tornado erc20 instance
   * @param uniPoolFee fee of the uniswap pool used to get prices
   * @param pool the tornado instance
   * @return poolId id of the pool
   * */
  function addPool(uint96 uniPoolFee, ITornadoInstance pool) external onlyRelayerRegistry returns (uint256 poolId) {
    poolId = _addPool(uniPoolFee, pool);
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
   * @param poolId the tornado pool id
   * @return fee for the pool
   * */
  function getFeeForPoolId(uint256 poolId) public view returns (uint256) {
    return getFeeForPool(getInstanceForPoolId[poolId]);
  }

  /**
   * @notice This function should get the fee for the pool via the instance as a key
   * @param pool the tornado instance
   * @return fee for the pool
   * */
  function getFeeForPool(ITornadoInstance pool) public view returns (uint256) {
    return getPoolDataForInstance[pool].protocolPoolFee;
  }

  /**
   * @notice This function should update the fees of each pool
   */
  function updateAllFees() public {
    for (uint256 i = 0; i < getInstanceForPoolId.length; i++) {
      updateFeeOfPool(i);
    }
    emit FeesUpdated(block.timestamp);
  }

  /**
   * @notice This function should update the fee of a specific pool
   * @param poolId id of the pool to update fees for
   */
  function updateFeeOfPool(uint256 poolId) public {
    ITornadoInstance instance = getInstanceForPoolId[poolId];
    getPoolDataForInstance[instance].protocolPoolFee = DataManager.updateSingleRegistryPoolFee(
      getPoolDataForInstance[instance],
      instance,
      dataForTWAPOracle
    );
    emit FeeUpdated(block.timestamp, poolId);
  }

  /**
   * @notice internal function to add a pool
   * @param uniPoolFee fee of the uniswap pool used to get prices (here irrelevant!)
   * @param pool the tornado instance
   */
  function _addPool(uint96 uniPoolFee, ITornadoInstance pool) internal returns (uint256) {
    getPoolDataForInstance[pool] = PoolData(
      uniPoolFee,
      DataManager.updateSingleRegistryPoolFee(PoolData(uniPoolFee, 0), pool, dataForTWAPOracle)
    );
    getInstanceForPoolId.push(pool);
    return getInstanceForPoolId.length - 1;
  }
}
