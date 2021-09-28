// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface ENS {
  function resolver(bytes32 node) external view returns (Resolver);

  function owner(bytes32 node) external view returns (address);
}

interface Resolver {
  function addr(bytes32 node) external view returns (address);
}

contract EnsResolve {
  address public constant ensAddress = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

  function resolve(bytes32 node) public view virtual returns (address) {
    return ENS(ensAddress).resolver(node).addr(node);
  }
}
