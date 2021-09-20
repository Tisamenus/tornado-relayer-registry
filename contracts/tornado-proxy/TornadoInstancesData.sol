// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { TornadoProxy } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

contract TornadoInstancesData {
  TornadoProxy.Tornado[] public Instances;

  constructor(TornadoProxy.Tornado[] memory instancesArray) public {
    for(uint256 i = 0; i < instancesArray.length; i++) {
      Instances.push(instancesArray[i]);
    }
  }

  function getInstances() external view returns (TornadoProxy.Tornado[] memory) {
    return Instances;
  }
}