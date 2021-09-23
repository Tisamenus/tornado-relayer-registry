// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RegistryDataManager, PoolData, GlobalPoolData } from "./RegistryDataManager.sol";

contract RelayerRegistryData {
  address public immutable governance;
  RegistryDataManager public immutable DataManager;

  PoolData[] public getPoolDataForPoolId;
  uint256[] public getFeeForPoolId;

  mapping(address => uint256) public getPoolIdForAddress;

  GlobalPoolData public protocolPoolData;

  uint256 public lastFeeUpdateTimestamp;

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
  }

  modifier onlyGovernance() {
    require(msg.sender == governance);
    _;
  }

  function updateAllFeesWithTimestampStore() external {
    lastFeeUpdateTimestamp = block.timestamp;
    updateAllFees();
  }

  function updateFeesOfPools(uint256[] memory poolIds) external {
    for (uint256 i = 0; i < poolIds.length; i++) {
      updateFeeOfPool(poolIds[i]);
    }
  }

  /**
  @dev Every time instances are added, governance needs to pass a proposal,
  so except contract initialization, we can let governance add any other pools
  should be updated together with relayer registry info
   */
  function addPool(uint96 uniPoolFee, address poolAddress) external onlyGovernance returns (uint256) {
    getPoolDataForPoolId.push(PoolData(uniPoolFee, poolAddress));
    getPoolIdForAddress[poolAddress] = getPoolDataForPoolId.length - 1;
    return getPoolDataForPoolId.length - 1;
  }

  function setProtocolFee(uint128 newFee) external onlyGovernance {
    protocolPoolData.protocolFee = newFee;
  }

  function setProtocolPeriod(uint128 newPeriod) external onlyGovernance {
    protocolPoolData.globalPeriod = newPeriod;
  }

  function updateAllFees() public {
    getFeeForPoolId = DataManager.updateRegistryDataArray(getPoolDataForPoolId, protocolPoolData);
  }

  function updateFeeOfPool(uint256 poolId) public {
    getFeeForPoolId[poolId] = DataManager.updateSingleRegistryDataArrayElement(
      getPoolDataForPoolId[poolId],
      protocolPoolData,
      poolId
    );
  }
}
