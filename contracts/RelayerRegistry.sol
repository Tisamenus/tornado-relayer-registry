// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/Initializable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./tornado-proxy/TornadoProxyRegistryUpgrade.sol";

interface ITornadoStakingRewards {
  function addBurnRewards(uint256 amount) external;
}

interface IENS {
  function owner(bytes32 node) external view returns (address);
}

struct RelayerMetadata {
  uint256 balance;
  bytes32 ensHash;
}

/**
 * @notice Registry contract, one of the main contracts of this protocol upgrade.
 *         The contract should store relayers' addresses and data attributed to the
 *         master address of the relayer. This data includes the relayers stake and
 *         his ensHash.
 *         A relayers master address has a number of subaddresses called "workers",
 *         these are all addresses which burn stake in communication with the proxy.
 *         If a relayer is not registered, he is not displayed on the frontend.
 * @dev CONTRACT RISKS:
 *      - if setter functions are compromised, relayer metadata would be at risk, including the noted amount of his balance
 *      - if burn function is compromised, relayers run the risk of being unable to handle withdrawals
 *      - the above risk also applies to the nullify balance function
 * */
contract RelayerRegistry is Initializable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant ensAddress = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
  IERC20 public constant torn = IERC20(0x77777FeDdddFfC19Ff86DB637967013e6C6A116C);

  address public governance;
  ITornadoStakingRewards public Staking;
  TornadoProxyRegistryUpgrade public TornadoProxy;

  uint256 public minStakeAmount;

  mapping(address => RelayerMetadata) public getMetadataForRelayer;
  mapping(address => address) public getMasterForWorker;

  event RelayerBalanceNullified(address indexed relayer);
  event WorkerRegistered(address indexed worker);
  event WorkerUnregistered(address indexed worker);
  event StakeAddedToRelayer(address indexed relayer, uint256 indexed amountStakeAdded);
  event StakeBurned(address indexed relayer, uint256 indexed amountBurned);
  event RewardsAddedByGovernance(uint256 indexed rewards);
  event NewMinimumStakeAmount(uint256 indexed minStakeAmount);
  event NewProxyRegistered(address indexed tornadoProxy);
  event NewRelayerRegistered(bytes32 relayer, address indexed relayerAddress, uint256 indexed stakedAmount);

  modifier onlyGovernance() {
    require(msg.sender == governance, "only governance");
    _;
  }

  modifier onlyTornadoProxy() {
    require(msg.sender == address(TornadoProxy), "only proxy");
    _;
  }

  modifier onlyENSOwner(bytes32 node) {
    require(msg.sender == IENS(ensAddress).owner(node), "only ens owner");
    _;
  }

  modifier onlyRelayer(address sender, address relayer) {
    require(getMasterForWorker[sender] == relayer, "only relayer");
    _;
  }

  /**
   * @notice initialize function for upgradeability
   * @dev this contract will be deployed behind a proxy and should not assign values at logic address,
   *      params left out because self explainable
   * */
  function initialize(address tornadoGovernance, address stakingAddress) external initializer {
    governance = tornadoGovernance;
    Staking = ITornadoStakingRewards(stakingAddress);
    getMasterForWorker[address(0)] = address(this);
  }

  /**
   * @notice This function should register a master address and optionally a set of workeres for a relayer + metadata
   * @dev Relayer can't steal other relayers workers since they are registered, and a wallet (msg.sender check) can always unregister itself
   * @param ensHash ensHash of the relayer
   * @param stake the initial amount of stake in TORN the relayer is depositing
   * */
  function register(
    bytes32 ensHash,
    uint256 stake,
    address[] memory workersToRegister
  ) external onlyENSOwner(ensHash) {
    require(getMasterForWorker[msg.sender] == address(0), "cant register again");
    RelayerMetadata storage metadata = getMetadataForRelayer[msg.sender];

    require(metadata.ensHash == bytes32(0), "registered already");
    require(stake >= minStakeAmount, "!min_stake");

    torn.safeTransferFrom(msg.sender, address(Staking), stake);
    emit StakeAddedToRelayer(msg.sender, stake);

    metadata.balance = stake;
    metadata.ensHash = ensHash;
    getMasterForWorker[msg.sender] = msg.sender;

    for (uint256 i = 0; i < workersToRegister.length; i++) {
      require(getMasterForWorker[workersToRegister[i]] == address(0), "can't steal an address");
      getMasterForWorker[workersToRegister[i]] = msg.sender;
    }

    emit NewRelayerRegistered(ensHash, msg.sender, stake);
  }

  /**
   * @notice This function should allow relayers to register more workeres
   * @param relayer Relayer which should send message from any worker which is already registered
   * @param worker Address to register
   * */
  function registerWorker(address relayer, address worker) external onlyRelayer(msg.sender, relayer) {
    require(getMasterForWorker[worker] == address(0), "can't steal an address");
    getMasterForWorker[worker] = relayer;
    emit WorkerRegistered(worker);
  }

  /**
   * @notice This function should allow anybody to unregister an address they own
   * @dev designed this way as to allow someone to unregister themselves in case a relayer misbehaves
   *      - this should be followed by an action like burning relayer stake
   *      - there was an option of allowing the sender to burn relayer stake in case of malicious behaviour, this feature was not included in the end
   *      - reverts if trying to unregister master, otherwise contract would break. in general, there should be no reason to unregister master at all
   * */
  function unregisterWorker(address worker) external {
    if (worker != msg.sender) require(getMasterForWorker[worker] == msg.sender, "only owner of worker");
    require(getMasterForWorker[worker] != worker, "cant unregister master");
    getMasterForWorker[worker] = address(0);
    emit WorkerUnregistered(worker);
  }

  /**
   * @notice This function should allow anybody to stake to a relayer more TORN
   * @param relayer Relayer main address to stake to
   * @param stake Stake to be added to relayer
   * */
  function stakeToRelayer(address relayer, uint256 stake) external {
    require(getMasterForWorker[relayer] == relayer, "!registered");
    torn.safeTransferFrom(msg.sender, address(Staking), stake);
    getMetadataForRelayer[relayer].balance = stake.add(getMetadataForRelayer[relayer].balance);
    emit StakeAddedToRelayer(relayer, stake);
  }

  /**
   * @notice This function should burn some relayer stake on withdraw and notify staking of this
   * @dev IMPORTANT FUNCTION:
   *      - This should be only called by the tornado proxy
   *      - Should revert if relayer does not call proxy from valid worker
   *      - Should not overflow
   *      - Should underflow and revert (SafeMath) on not enough stake (balance)
   * @param sender worker to check sender == relayer
   * @param relayer address of relayer who's stake is being burned
   * @param pool instance to get fee for
   * */
  function burn(
    address sender,
    address relayer,
    ITornadoInstance pool
  ) external onlyTornadoProxy {
    address masterAddress = getMasterForWorker[sender];
    if (masterAddress == address(0)) return;
    require(masterAddress == relayer, "only relayer");
    uint256 toBurn = TornadoProxy.getFeeForPool(pool);
    getMetadataForRelayer[relayer].balance = getMetadataForRelayer[relayer].balance.sub(toBurn);
    Staking.addBurnRewards(toBurn);
    emit StakeBurned(relayer, toBurn);
  }

  /**
   * @notice This function should allow governance to set the minimum stake amount
   * @param minAmount new minimum stake amount
   * */
  function setMinStakeAmount(uint256 minAmount) external onlyGovernance {
    minStakeAmount = minAmount;
    emit NewMinimumStakeAmount(minAmount);
  }

  /**
   * @notice This function should allow governance to set a new tornado proxy address
   * @param tornadoProxyAddress address of the new proxy
   * */
  function registerProxy(address tornadoProxyAddress) external onlyGovernance {
    TornadoProxy = TornadoProxyRegistryUpgrade(tornadoProxyAddress);
    emit NewProxyRegistered(tornadoProxyAddress);
  }

  /**
   * @notice This function should allow governance to nullify a relayers balance
   * @dev IMPORTANT FUNCTION:
   *      - Should nullify the balance
   *      - Adding nullified balance as rewards was refactored to allow for the flexibility of these funds (for gov to operate with them)
   * @param relayer address of relayer who's balance is to nullify
   * */
  function nullifyBalance(address relayer) external onlyGovernance {
    address masterAddress = getMasterForWorker[relayer];
    require(relayer == masterAddress, "must be master");
    getMetadataForRelayer[masterAddress].balance = 0;
    emit RelayerBalanceNullified(relayer);
  }

  /**
   * @notice This function should check if a worker is associated with a relayer
   * @param toResolve address to check
   * @return true if is associated
   * */
  function isRelayer(address toResolve) external view returns (bool) {
    return getMasterForWorker[toResolve] != address(0);
  }

  /**
   * @notice This function should check if a worker is registered to the relayer stated
   * @param relayer relayer to check
   * @param toResolve address to check
   * @return true if registered
   * */
  function isRelayerRegistered(address relayer, address toResolve) external view returns (bool) {
    return getMasterForWorker[toResolve] == relayer;
  }

  /**
   * @notice This function should get a relayers ensHash
   * @param relayer address to fetch for
   * @return relayer's ensHash
   * */
  function getRelayerEnsHash(address relayer) external view returns (bytes32) {
    return getMetadataForRelayer[getMasterForWorker[relayer]].ensHash;
  }

  /**
   * @notice This function should get a relayers balance
   * @param relayer relayer who's balance is to fetch
   * @return relayer's balance
   * */
  function getRelayerBalance(address relayer) external view returns (uint256) {
    return getMetadataForRelayer[getMasterForWorker[relayer]].balance;
  }
}
