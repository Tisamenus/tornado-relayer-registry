// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "tornado-anonymity-mining/contracts/TornadoProxy.sol";

interface IRelayerRegistry {
  function burn(
    address sender,
    address relayer,
    ITornadoInstance pool
  ) external;

  function addPool(uint96 uniPoolFee, ITornadoInstance pool) external;
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

  function getPoolToken(ITornadoInstance instance) external view returns (address) {
    return address(instances[instance].token);
  }

  function addInstance(uint96 uniPoolFee, Tornado calldata _tornado) external virtual onlyGovernance {
    _updateInstance(_tornado);
    Registry.addPool(uniPoolFee, _tornado.addr);
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
    if (_relayer != address(0)) Registry.burn(msg.sender, _relayer, _tornado);

    super.withdraw(_tornado, _proof, _root, _nullifierHash, _recipient, _relayer, _fee, _refund);
  }
}
