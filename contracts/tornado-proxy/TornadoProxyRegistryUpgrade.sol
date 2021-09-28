// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { TornadoProxy, ITornadoInstance } from "tornado-anonymity-mining/contracts/TornadoProxy.sol";

interface IRelayerRegistry {
  function burn(address relayer, address poolAddress) external;
}

contract TornadoProxyRegistryUpgrade is TornadoProxy {
  IRelayerRegistry public immutable Registry;

  constructor(
    address registryAddress,
    address tornadoTrees,
    address governance,
    Tornado[] memory instances
  ) public TornadoProxy(tornadoTrees, governance, instances) {
    Registry = IRelayerRegistry(registryAddress);
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
  ) public payable virtual override {
    if (_relayer != address(0)) Registry.burn(_relayer, address(_tornado));

    super.withdraw(_tornado, _proof, _root, _nullifierHash, _recipient, _relayer, _fee, _refund);
  }
}
