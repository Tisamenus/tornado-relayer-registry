# Tornado Relayer Registry

[![Build Status](https://img.shields.io/github/workflow/status/Tisamenus/tornado-relayer-registry/build)](https://github.com/h-ivor/tornado-relayer-registry/actions) [![Coverage Status](https://img.shields.io/coveralls/github/Tisamenus/tornado-relayer-registry)](https://coveralls.io/github/Tisamenus/tornado-relayer-registry?branch=new)

Repository for a governance upgrade which includes a registry for relayer registration and staking mechanisms for the torn token.

# Overview

1. Anyone can become a relayer by staking TORN into Registry contract.
2. Minimum stake is governed by the Governance.
3. Each Pool has its own fee % which is also set by the Governance.
4. On every withdrawal via relayer, the relayer has to pay the Tornado Pool fee in TORN.
The fee is deducted from his staked balance.
6. All collected fees are stored into StakingReward contract.
7. Any TORN holder can stake their TORN into Governance contract like they were before, but
earning fees proportionately to their stake.

Caveats:
Anyone can trigger price oracle update in order to adjust the calculation of how much TORN should be deducted.
It uses Uniswap V3 TWAP oracle model.

## Setup

```bash
git clone --recurse-submodules https://github.com/Tisamenus/tornado-relayer-registry.git
cd tornado-relayer-registry
yarn
cp .env.example .env
yarn test
```

### Architecture

This will be a top-down look on the architecture.

#### RelayerRegistryProposal.sol

The governance proposal, which if executed by some party, should upgrade governance to a new version and initialize the data of all of the contracts which require data initalization outside of their construction scope.

This is for: 1. circular dependencies (one contract receives and address at construction while the other needs to register it if not being deployed by it) 2. community decided and other hardcoded parameters for regular contract functioning, 3. other necessary actions such as initializations for proxies.

This contract is not called directly and instead only the logic is used by a contract that calls it (governance). Thus, if delegatecalled, the calling contract communicates with:

1. The Relayer Registry.
2. The old Tornado Proxy.
3. The new Tornado Proxy (TornadoProxyRegistryUpgrade).
4. The Trees Contract.

#### RelayerRegistry.sol

This contract should store the data of each relayer, including their balance, which should be burned on withdrawals. It also stores any addresses the relayer decides to register under its own master address. When a withdrawal happens the contract decrements a relayers balance and calls the staking contract to increment the rewards.

Communicates with:

1. The new Tornado Proxy.
2. The Staking contract.
3. The Governance contract.
4. Relayers and user accounts.

#### TornadoProxyRegistryUpgrade.sol

This contract should upgrade the Tornado Proxy to include the following functionalities:

- Updating rewards for individual stakers on lock and unlock.
- Storing and updating the fee balance of relayers registered in the relayer registry.
- Starting the burn procedure on relayer withdrawal.
- All legacy proxy functionality.

Communicates with:

1. The Relayer Registry.
2. The Governance contract.
3. The Pool Fee Calculator.
4. Relayers and user accounts

#### PoolFeeCalculator.sol

This is an upgradeable contract which should calculate the correct fee for tornado pool withdrawals. This is contract will be deployed behind a proxy thus making logic upgradeable.

Communicates with:

1. The new Tornado Proxy.

#### TornadoStakingRewards.sol

This contract should store relayer-staked torn and distribute it (update rewards) to accounts which have locked torn in governance. Each time a relayer withdraws, the amount of torn burned is added as rewards according to the SNX logic. Any account can then withdraw.

Communicates with:

1. The Relayer Registry.
2. The Governance Contract;
3. User accounts.
