// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { TornadoProxy, ITornadoInstance } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

interface IRelayerRegistry {
  function burn(bytes32 relayer, address poolAddress) external;

  function getRelayerForAddress(address relayer) external returns (bytes32);
}

contract TornadoProxyRegistryUpgrade is TornadoProxy {
  IRelayerRegistry public immutable registry;

  constructor(
    address registryAddress,
    address tornadoTrees,
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
    Instance memory instance = instances[_tornado];
    require(instance.state != InstanceState.DISABLED, "The instance is not supported");

    _tornado.withdraw{ value: msg.value }(_proof, _root, _nullifierHash, _recipient, _relayer, _fee, _refund);
    if (instance.state == InstanceState.MINEABLE) {
      tornadoTrees.registerWithdrawal(address(_tornado), _nullifierHash);
    }
  }
}
