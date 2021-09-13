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

  constructor(address _dataManagerProxy, address _tornadoGovernance) public {
    DataManager = RegistryDataManager(_dataManagerProxy);
    Governance = _tornadoGovernance;
  }

  modifier onlyGovernance() {
    require(msg.sender == Governance);
    _;
  }

  function updateFees() external {
    getFeeForPoolId = DataManager.updateRegistryDataArray(getPoolDataForPoolId, protocolPoolData);
  }

  function setProtocolFee(uint128 _newFee) external onlyGovernance {
    protocolPoolData.protocolFee = _newFee;
  }

  function setProtocolPeriod(uint128 _newPeriod) external onlyGovernance {
    protocolPoolData.globalPeriod = _newPeriod;
  }
}
