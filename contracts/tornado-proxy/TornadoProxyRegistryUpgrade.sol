// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./ModifiedTornadoProxy.sol";
import "../registry-data/RegistryDataManager.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IRelayerRegistry {
  function burn(
    address sender,
    address relayer,
    ITornadoInstance pool
  ) external;

  function addPool(uint96 uniPoolFee, ITornadoInstance pool) external;
}

contract TornadoProxyRegistryUpgrade is ModifiedTornadoProxy, ReentrancyGuard {
  IRelayerRegistry public immutable Registry;
  RegistryDataManager public immutable DataManager;

  ITornadoInstance[] public getInstanceForPoolId;
  GlobalPoolData public dataForTWAPOracle;

  event FeesUpdated(uint256 indexed timestamp);
  event FeeUpdated(uint256 indexed timestamp, uint256 indexed poolId);

  constructor(
    address registryAddress,
    address dataManagerAddress,
    address tornadoTrees,
    address governance,
    Tornado[] memory instances
  ) public ModifiedTornadoProxy(tornadoTrees, governance, instances) {
    Registry = IRelayerRegistry(registryAddress);
    DataManager = RegistryDataManager(dataManagerAddress);

    for (uint256 i = 0; i < instances.length; i++) {
      getInstanceForPoolId.push(instances[i].addr);
    }
  }

  /// @notice function which should allow a user to withdraw from a tornado instance
  /// @dev at 100 GWEI, the nonReentrant costs approximately 0.9$ extra in a transaction, but this is to stop
  ///      somebody from calling burn repeatedly on a relayer
  ///      - f arguments are the same as in base contract (non-modified and modified version)
  function withdraw(
    ITornadoInstance _tornado,
    bytes calldata _proof,
    bytes32 _root,
    bytes32 _nullifierHash,
    address payable _recipient,
    address payable _relayer,
    uint256 _fee,
    uint256 _refund
  ) public payable virtual override nonReentrant {
    if (_relayer != address(0)) Registry.burn(msg.sender, _relayer, _tornado);
    super.withdraw(_tornado, _proof, _root, _nullifierHash, _recipient, _relayer, _fee, _refund);
  }

  /// @notice updated "updateInstance" function, which should now update the pool fee when updating an instances data
  /// @dev adds the instance when uniPoolFee == 0 because this is pool specific and first time assigned != 0 at first updat
  ///      - call should also break because of update if fee is invalid
  function updateInstance(Tornado memory _tornado) external virtual override onlyGovernance {
    _tornado.instance.poolData.poolFee = DataManager.updateSingleRegistryPoolFee(
      _tornado.addr,
      _tornado.instance,
      dataForTWAPOracle
    );
    if (instances[_tornado.addr].poolData.uniPoolFee == 0) getInstanceForPoolId.push(_tornado.addr);
    _updateInstance(_tornado);
  }


  /// @notice get erc20 tornado instance token
  /// @param instance the interface (contract) key to the instance data
  function getPoolToken(ITornadoInstance instance) external view returns (address) {
    return address(instances[instance].token);
  }

  /**
   * @notice This function should allow governance to set a new protocol fee for relayers
   * @param newFee the new fee to use
   * */
  function setProtocolFee(uint128 newFee) external onlyGovernance {
    dataForTWAPOracle.protocolFee = newFee;
  }

  /**
   * @notice This function should allow governance to set a new period for twap measurement
   * @param newPeriod the new period to use
   * */
  function setPeriodForTWAPOracle(uint128 newPeriod) external onlyGovernance {
    dataForTWAPOracle.globalPeriod = newPeriod;
  }

  /**
   * @notice This function should get the fee for the pool address in one go
   * @param poolId the tornado pool id
   * @return fee for the pool
   * */
  function getFeeForPoolId(uint256 poolId) public view returns (uint256) {
    return getFeeForPool(getInstanceForPoolId[poolId]);
  }

  /**
   * @notice This function should get the fee for the pool via the instance as a key
   * @param pool the tornado instance
   * @return fee for the pool
   * */
  function getFeeForPool(ITornadoInstance pool) public view returns (uint256) {
    return instances[pool].poolData.poolFee;
  }

  /**
   * @notice This function should update the fees of each pool
   */
  function updateAllFees() public {
    for (uint256 i = 0; i < getInstanceForPoolId.length; i++) {
      updateFeeOfPool(i);
    }
    emit FeesUpdated(block.timestamp);
  }

  /**
   * @notice This function should update the fees for poolIds tornado instances
   *         (here called pools)
   * @param poolIds poolIds to update fees for
   * */
  function updateFeesOfPools(uint256[] memory poolIds) public {
    for (uint256 i = 0; i < poolIds.length; i++) {
      updateFeeOfPool(poolIds[i]);
    }
  }

  /**
   * @notice This function should update the fee of a specific pool
   * @param poolId id of the pool to update fees for
   */
  function updateFeeOfPool(uint256 poolId) public {
    ITornadoInstance instance = getInstanceForPoolId[poolId];
    instances[instance].poolData.poolFee = DataManager.updateSingleRegistryPoolFee(
      instance,
      instances[instance],
      dataForTWAPOracle
    );
    emit FeeUpdated(block.timestamp, poolId);
  }
}
