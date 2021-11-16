// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "tornado-anonymity-mining/contracts/interfaces/ITornadoInstance.sol";
import "tornado-anonymity-mining/contracts/interfaces/ITornadoTrees.sol";

import "./PoolFeeCalculator.sol";
import "../RelayerRegistry.sol";

contract TornadoRouter {
  using SafeERC20 for IERC20;

  address public immutable governance;

  TornadoInstances public instances;
  ITornadoTrees public tornadoTrees;
  RelayerRegistry public registry;

  event TornadoTreesUpdated(address addr);
  event RelayerRegistryUpdated(address addr);
  event TornadoInstancesUpdated(address addr);
  event EncryptedNote(address indexed sender, bytes encryptedNote);

  constructor(
    address _tornadoTrees,
    address _governance,
    address _registry
  ) public {
    tornadoTrees = ITornadoTrees(_tornadoTrees);
    registry = RelayerRegistry(_registry);
    governance = _governance;
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, "Not authorized");
    _;
  }

  modifier onlyInstances() {
    require(msg.sender == address(instances), "Not authorized");
    _;
  }

  function deposit(
    ITornadoInstance _tornado,
    bytes32 _commitment,
    bytes calldata _encryptedNote
  ) public payable virtual {
    Instance memory instance = instances.getInstance(_tornado);
    require(InstanceState(instance.state) != InstanceState.DISABLED, "The instance is not supported");

    if (instance.isERC20) {
      instance.token.safeTransferFrom(msg.sender, address(this), _tornado.denomination());
    }
    _tornado.deposit{ value: msg.value }(_commitment);

    if (InstanceState(instance.state) == InstanceState.MINEABLE) {
      tornadoTrees.registerDeposit(address(_tornado), _commitment);
    }
    emit EncryptedNote(msg.sender, _encryptedNote);
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
  ) public payable virtual {
    registry.burn(msg.sender, _relayer, _tornado);

    Instance memory instance = instances.getInstance(_tornado);
    require(InstanceState(instance.state) != InstanceState.DISABLED, "The instance is not supported");

    _tornado.withdraw{ value: msg.value }(_proof, _root, _nullifierHash, _recipient, _relayer, _fee, _refund);

    if (InstanceState(instance.state) == InstanceState.MINEABLE) {
      tornadoTrees.registerWithdrawal(address(_tornado), _nullifierHash);
    }
  }

  function backupNotes(bytes[] calldata _encryptedNotes) external virtual {
    for (uint256 i = 0; i < _encryptedNotes.length; i++) {
      emit EncryptedNote(msg.sender, _encryptedNotes[i]);
    }
  }

  function setTornadoTreesContract(address _tornadoTrees) external virtual onlyGovernance {
    tornadoTrees = ITornadoTrees(_tornadoTrees);
    emit TornadoTreesUpdated(_tornadoTrees);
  }

  function setRegistryContract(address _registry) external virtual onlyGovernance {
    registry = RelayerRegistry(_registry);
    emit RelayerRegistryUpdated(_registry);
  }

  function setInstancesContract(address _instances) external virtual onlyGovernance {
    instances = TornadoInstances(_instances);
    emit TornadoInstancesUpdated(_instances);
  }

  function rescueTokens(
    IERC20 _token,
    address payable _to,
    uint256 _amount
  ) external virtual onlyGovernance {
    require(_to != address(0), "TORN: can not send to zero address");

    if (_token == IERC20(0)) {
      // for Ether
      uint256 totalBalance = address(this).balance;
      uint256 balance = Math.min(totalBalance, _amount);
      _to.transfer(balance);
    } else {
      // any other erc20
      uint256 totalBalance = _token.balanceOf(address(this));
      uint256 balance = Math.min(totalBalance, _amount);
      require(balance > 0, "TORN: trying to send 0 balance");
      _token.safeTransfer(_to, balance);
    }
  }

  function callSafeApprove(
    IERC20 token,
    address spender,
    uint256 amount
  ) public virtual onlyInstances {
    token.safeApprove(spender, amount);
  }
}
