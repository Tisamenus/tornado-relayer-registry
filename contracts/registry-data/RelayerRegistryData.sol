// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { RegistryDataManager, PoolData, GlobalPoolData } from "./RegistryDataManager.sol";

contract RelayerRegistryData {
  address public immutable Governance;
  RegistryDataManager public immutable DataManager;

  PoolData[] public getPoolDataForPoolId;
  uint256[] public getFeeForPoolId;

  GlobalPoolData public protocolPoolData;

  constructor(
    address dataManagerProxy,
    address tornadoGovernance,
    uint96[] memory initPoolDataFees,
    address[] memory initPoolDataAddresses
  ) public {
    DataManager = RegistryDataManager(dataManagerProxy);
    Governance = tornadoGovernance;

    for (uint256 i = 0; i < initPoolDataFees.length; i++) {
      getPoolDataForPoolId.push(PoolData(initPoolDataFees[i], initPoolDataAddresses[i]));
    }
  }

  modifier onlyGovernance() {
    require(msg.sender == Governance);
    _;
  }

  function updateFees() external {
    getFeeForPoolId = DataManager.updateRegistryDataArray(getPoolDataForPoolId, protocolPoolData);
  }

  /**
  @dev Every time instances are added, governance needs to pass a proposal,
  so except contract initialization, we can let governance add any other pools
  should be updated together with relayer registry info
   */
  function addPool(uint96 uniPoolFee, address poolAddress) external onlyGovernance returns (uint256) {
    getPoolDataForPoolId.push(PoolData(uniPoolFee, poolAddress));
    return getPoolDataForPoolId.length - 1;
  }

  function setProtocolFee(uint128 newFee) external onlyGovernance {
    protocolPoolData.protocolFee = newFee;
  }

  function setProtocolPeriod(uint128 newPeriod) external onlyGovernance {
    protocolPoolData.globalPeriod = newPeriod;
  }
}
