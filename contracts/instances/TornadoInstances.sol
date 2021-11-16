// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./TornadoRouter.sol";
import "./PoolFeeCalculator.sol";

enum InstanceState {
  DISABLED,
  ENABLED,
  MINEABLE
}

/// @param isERC20 is the instance an ERC20
/// @param token erc20 token
/// @param state represents InstanceState, but 88 to pack efficiently with above
/// @param poolData seconds storage slot, see PoolFeeCalculator.sol
struct Instance {
  bool isERC20;
  IERC20 token;
  uint88 state;
  PoolData poolData;
}

struct Tornado {
  ITornadoInstance addr;
  Instance instance;
}

contract TornadoInstances {
  PoolFeeCalculator public immutable DataManager;

  address public governance;

  ITornadoInstance[] public getInstanceForPoolId;
  ProxyPoolParameters public dataForTWAPOracle;
  TornadoRouter public tornadoRouter;

  mapping(ITornadoInstance => Instance) public instances;

  event FeesUpdated(uint256 indexed timestamp);
  event FeeUpdated(uint256 indexed timestamp, uint256 indexed poolId);
  event InstanceUpdated(ITornadoInstance indexed instance, InstanceState state, PoolData poolData);

  constructor(
    address dataManagerAddress,
    address governanceAddress,
    address tornadoRouterAddress,
    Tornado[] memory instancesArray
  ) public {
    DataManager = PoolFeeCalculator(dataManagerAddress);
    governance = governanceAddress;
    tornadoRouter = TornadoRouter(tornadoRouterAddress);

    for (uint256 i = 0; i < instancesArray.length; i++) {
      getInstanceForPoolId.push(instancesArray[i].addr);
      _updateInstance(instancesArray[i]);
    }
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, "Not authorized");
    _;
  }

  /// @notice updated "updateInstance" function, which should now update the pool fee when updating an instances data
  /// @dev adds the instance when uniPoolFee == 0 because this is pool specific and first time assigned != 0 at first update
  ///      - call should also break because of update if fee is invalid
  function updateInstance(Tornado memory tornado) external virtual onlyGovernance {
    tornado.instance.poolData.tornFeeOfPool = DataManager.calculateSingleRegistryPoolFee(
      tornado.addr,
      tornado.instance,
      dataForTWAPOracle
    );

    if (instances[tornado.addr].poolData.uniswapPoolSwappingFee == 0) getInstanceForPoolId.push(tornado.addr);
    _updateInstance(tornado);
  }

  /// @notice This function should update the fees of each pool
  function updateAllFees() external {
    for (uint256 i = 0; i < getInstanceForPoolId.length; i++) {
      updateFeeOfPool(i);
    }
    emit FeesUpdated(block.timestamp);
  }

  /// @notice This function should update the fees for poolIds tornado instances
  ///         (here called pools)
  /// @param poolIds poolIds to update fees for
  function updateFeesOfPools(uint256[] memory poolIds) external {
    for (uint256 i = 0; i < poolIds.length; i++) {
      updateFeeOfPool(poolIds[i]);
    }
  }

  /// @notice This function should allow governance to set a new protocol fee for relayers
  /// @param newFee the new fee to use
  function setProtocolFee(uint128 newFee) external onlyGovernance {
    dataForTWAPOracle.proxyFee = newFee;
  }

  /// @notice This function should allow governance to set a new period for twap measurement
  /// @param newPeriod the new period to use
  function setPeriodForTWAPOracle(uint128 newPeriod) external onlyGovernance {
    dataForTWAPOracle.uniswapTimePeriod = newPeriod;
  }

  /// @notice This function should return the entire "Instance" data struct for the router and other contracts
  function getInstance(ITornadoInstance instance) external view returns (Instance memory) {
    return instances[instance];
  }

  /// @notice get erc20 tornado instance token
  /// @param instance the interface (contract) key to the instance data
  function getPoolToken(ITornadoInstance instance) external view returns (address) {
    return address(instances[instance].token);
  }

  /// @notice This function should return a pools state
  function getPoolStateForPoolId(uint256 poolId) external view returns (InstanceState) {
    return getPoolStateForPool(getInstanceForPoolId[poolId]);
  }

  /// @notice This function should get the fee for the pool address in one go
  /// @param poolId the tornado pool id
  /// @return fee for the pool
  function getFeeForPoolId(uint256 poolId) external view returns (uint256) {
    return getFeeForPool(getInstanceForPoolId[poolId]);
  }

  function getNumberOfInstances() external view returns (uint256) {
    return getInstanceForPoolId.length;
  }

  /// @notice This function should update the fee of a specific pool
  /// @param poolId id of the pool to update fees for
  function updateFeeOfPool(uint256 poolId) public {
    ITornadoInstance instance = getInstanceForPoolId[poolId];
    instances[instance].poolData.tornFeeOfPool = DataManager.calculateSingleRegistryPoolFee(
      instance,
      instances[instance],
      dataForTWAPOracle
    );
    emit FeeUpdated(block.timestamp, poolId);
  }

  ///  @notice This function should get the fee for the pool via the instance as a key
  ///  @param pool the tornado instance
  ///  @return fee for the pool
  function getFeeForPool(ITornadoInstance pool) public view returns (uint256) {
    return instances[pool].poolData.tornFeeOfPool;
  }

  function getPoolStateForPool(ITornadoInstance instance) public view returns (InstanceState) {
    return InstanceState(instances[instance].state);
  }

  function _updateInstance(Tornado memory tornado) internal virtual {
    instances[tornado.addr] = tornado.instance;

    if (tornado.instance.isERC20) {
      IERC20 token = IERC20(tornado.addr.token());
      require(token == tornado.instance.token, "Incorrect token");

      uint256 allowance = token.allowance(address(tornadoRouter), address(tornado.addr));

      if (InstanceState(tornado.instance.state) != InstanceState.DISABLED && allowance == 0) {
        tornadoRouter.callSafeApprove(token, address(tornado.addr), uint256(-1));
      } else if (InstanceState(tornado.instance.state) == InstanceState.DISABLED && allowance != 0) {
        tornadoRouter.callSafeApprove(token, address(tornado.addr), 0);
      }

      emit InstanceUpdated(tornado.addr, InstanceState(tornado.instance.state), tornado.instance.poolData);
    }
  }
}
