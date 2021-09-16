// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { TornadoProxy, Tornado } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

interface IRelayerRegistry {
  function burn(bytes32 relayer, address poolAddress) external;

  function getAddressForRelayer(bytes32 relayer) external returns (address);
}

contract TornadoProxyRegistryUpgrade is TornadoProxy {
  IRelayerRegistry public immutable registry;

  constructor(
    address registryAddress,
    address tornadoTress,
    address governance,
    Tornado[] memory instances
  ) public TornadoProxy(tornadoTrees, governance, instances) {
    registry = IRelayerRegistry(registryAddress);
  }

  function withdraw(
    ITornadoInstance _tornado,
    bytes calldata _proof,
    bytes32 _root,
    bytes32 _nullifierHash,
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) external payable virtual override {
    registry.burn(registry.getRelayerForAddress(_relayer), address(_tornado));
    super.withdraw(_tornado, _proof, _root, _nullifierHash, _recipient, _relayer, _fee, _refund);
  }
}
