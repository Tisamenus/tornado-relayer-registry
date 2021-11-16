const { ethers } = require('hardhat')
const { expect } = require('chai')
const { mainnet } = require('./tests.data.json')
const { token_addresses } = mainnet
const { torn, dai } = token_addresses
const { BigNumber } = require('@ethersproject/bignumber')
const { rbigint, createDeposit, toHex, generateProof, initialize } = require('tornado-cli')
const MixerABI = require('tornado-cli/build/contracts/Mixer.abi.json')

describe('Malicious tests', () => {
  /// NAME HARDCODED
  let governance = mainnet.tornado_cash_addresses.governance

  let tornadoPools = mainnet.project_specific.contract_construction.RelayerRegistryData.tornado_pools
  let uniswapPoolFees = mainnet.project_specific.contract_construction.RelayerRegistryData.uniswap_pool_fees
  let poolTokens = mainnet.project_specific.contract_construction.RelayerRegistryData.pool_tokens
  let feesArray = [
    100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100,
  ]

  let salt = '0x746f726e61646f00000000000000000000000000000000000000000000000000' //  "tornado"
  let singletonFactoryAddress = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

  let tornadoTrees = mainnet.tornado_cash_addresses.trees
  let tornadoProxy = mainnet.tornado_cash_addresses.tornado_proxy

  let approxVaultBalance = ethers.utils.parseUnits('13893131191552333230524', 'wei')

  //// CONTRACTS / FACTORIES
  let SingletonFactory
  let Create2ComputerFactory
  let Create2Computer

  let ProxyFactory

  let FeeCalculatorFactory
  let FeeCalculatorProxy
  let FeeCalculator

  let RelayerRegistry
  let RelayerRegistryImplementation
  let RegistryFactory

  let StakingFactory
  let StakingContract

  let TornadoInstances = []

  let TornadoProxyFactory
  let TornadoProxy

  let Governance

  let GasCompensationFactory
  let GasCompensation

  let Proposal
  let ProposalFactory

  let MockVault
  let MockVaultFactory

  //// IMPERSONATED ACCOUNTS
  let tornWhale
  let daiWhale
  let relayers = []
  let impGov

  //// NORMAL ACCOUNTS
  let signerArray

  //// HELPER FN
  let sendr = async (method, params) => {
    return await ethers.provider.send(method, params)
  }

  let getToken = async (tokenAddress) => {
    return await ethers.getContractAt('@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20', tokenAddress)
  }

  let erc20Transfer = async (tokenAddress, senderWallet, recipientAddress, amount) => {
    const token = (await getToken(tokenAddress)).connect(senderWallet)
    return await token.transfer(recipientAddress, amount)
  }

  let minewait = async (time) => {
    await ethers.provider.send('evm_increaseTime', [time])
    await ethers.provider.send('evm_mine', [])
  }

  before(async function () {
    signerArray = await ethers.getSigners()

    /// CREATE2 CONTRACTS
    SingletonFactory = await ethers.getContractAt('SingletonFactory', singletonFactoryAddress)
    Create2ComputerFactory = await ethers.getContractFactory('Create2Computer')
    Create2Computer = await Create2ComputerFactory.deploy()

    //// PROXY DEPLOYMENTS
    FeeCalculatorFactory = await ethers.getContractFactory('PoolFeeCalculator')
    ProxyFactory = await ethers.getContractFactory('AdminUpgradeableProxy')

    //// READ IN
    MockVaultFactory = await ethers.getContractFactory('TornadoVault')
    MockVault = await MockVaultFactory.deploy()

    //// POOL DATA

    for (let i = 0; i < tornadoPools.length; i++) {
      const PoolData = {
        uniswapPoolSwappingFee: uniswapPoolFees[i],
        tornFeeOfPool: feesArray[i],
      }
      const Instance = {
        isERC20: i > 3,
        token: token_addresses[poolTokens[i]],
        state: 2,
        poolData: PoolData,
      }
      const Tornado = {
        addr: tornadoPools[i],
        instance: Instance,
      }
      TornadoInstances[i] = Tornado
    }

    ///// CREATE2 BLOCK /////////////////////////////////////////////////////////////////////////
    /////////////// DATA MANAGER
    await SingletonFactory.deploy(FeeCalculatorFactory.bytecode, salt)
    const deploymentAddressManager = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(FeeCalculatorFactory.bytecode),
      SingletonFactory.address,
    )

    FeeCalculator = await ethers.getContractAt('PoolFeeCalculator', deploymentAddressManager)

    /////////////// DATA MANAGER PROXY
    const proxyDeploymentBytecode =
      ProxyFactory.bytecode +
      ProxyFactory.interface.encodeDeploy([FeeCalculator.address, governance, []]).slice(2)

    await SingletonFactory.deploy(proxyDeploymentBytecode, salt)

    const deploymentAddressManagerProxy = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(proxyDeploymentBytecode),
      SingletonFactory.address,
    )

    FeeCalculatorProxy = await ethers.getContractAt('PoolFeeCalculator', deploymentAddressManagerProxy)

    /////////////// RELAYER REGISTRY
    RegistryFactory = await ethers.getContractFactory('RelayerRegistry')
    await SingletonFactory.deploy(RegistryFactory.bytecode, salt)

    const deploymentAddressRegistry = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(RegistryFactory.bytecode),
      SingletonFactory.address,
    )
    RelayerRegistryImplementation = await ethers.getContractAt('RelayerRegistry', deploymentAddressRegistry)

    /////////////// RELAYER REGISTRY PROXY

    const registryProxyDeploymentBytecode =
      ProxyFactory.bytecode +
      ProxyFactory.interface.encodeDeploy([RelayerRegistryImplementation.address, governance, []]).slice(2)

    await SingletonFactory.deploy(registryProxyDeploymentBytecode, salt)

    const deploymentAddressRegistryProxy = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(registryProxyDeploymentBytecode),
      SingletonFactory.address,
    )

    RelayerRegistry = await ethers.getContractAt('RelayerRegistry', deploymentAddressRegistryProxy)

    /////////////// STAKING

    StakingFactory = await ethers.getContractFactory('TornadoStakingRewards')

    const deploymentBytecodeStaking =
      StakingFactory.bytecode +
      StakingFactory.interface.encodeDeploy([governance, RelayerRegistry.address, torn]).slice(2)

    await SingletonFactory.deploy(deploymentBytecodeStaking, salt)

    const deploymentAddressStaking = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(deploymentBytecodeStaking),
      SingletonFactory.address,
    )

    StakingContract = await ethers.getContractAt('TornadoStakingRewards', deploymentAddressStaking)

    /////////////// TORNADO PROXY
    TornadoProxyFactory = await ethers.getContractFactory('TornadoProxyRegistryUpgrade')

    const deploymentBytecodeTornadoProxy =
      TornadoProxyFactory.bytecode +
      TornadoProxyFactory.interface
        .encodeDeploy([
          RelayerRegistry.address,
          FeeCalculatorProxy.address,
          tornadoTrees,
          governance,
          TornadoInstances.slice(0, TornadoInstances.length - 1),
        ])
        .slice(2)

    await SingletonFactory.deploy(deploymentBytecodeTornadoProxy, salt)

    const deploymentAddressTornadoProxy = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(deploymentBytecodeTornadoProxy),
      SingletonFactory.address,
    )

    TornadoProxy = await ethers.getContractAt('TornadoProxyRegistryUpgrade', deploymentAddressTornadoProxy)

    console.log('Exp. addr. TornadoProxy: ', deploymentAddressTornadoProxy)
    console.log('Exp. addr. Staking: ', deploymentAddressStaking)
    console.log('Exp. addr. RegistryProxy: ', deploymentAddressRegistryProxy)
    console.log('Exp. addr. RelayerRegistry: ', deploymentAddressRegistry)
    console.log('Exp. addr. ManagerProxy: ', deploymentAddressManagerProxy)
    console.log('Exp. addr. FeeCalculator: ', deploymentAddressManager)
    //////////////////////////////////////////////////////////////////////////////////////////

    GasCompensationFactory = await ethers.getContractFactory('GasCompensationVault')
    GasCompensation = await GasCompensationFactory.deploy()

    ////////////// PROPOSAL OPTION 1
    ProposalFactory = await ethers.getContractFactory(
      process.env.use_mock_proposal == 'true' ? 'MockProposal' : 'RelayerRegistryProposal',
    )
    Proposal = await ProposalFactory.deploy(tornadoProxy, GasCompensation.address, MockVault.address)

    Governance = await ethers.getContractAt('GovernanceStakingUpgrade', governance)
  })

  describe('Start of tests', () => {
    describe('Account setup procedure', () => {
      it('Should successfully imitate a torn whale', async function () {
        await sendr('hardhat_impersonateAccount', ['0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3'])
        tornWhale = await ethers.getSigner('0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3')
      })

      it('Should successfully imitate governance to transfer torn to vault,\n since we do this in the former proposal', async () => {
        await sendr('hardhat_impersonateAccount', [Governance.address])
        await sendr('hardhat_setBalance', [Governance.address, '0xDE0B6B3A7640000'])
        impGov = await ethers.getSigner(Governance.address)
        const govTorn = (await await getToken(torn)).connect(impGov)

        await expect(() => govTorn.transfer(MockVault.address, approxVaultBalance)).to.changeTokenBalance(
          await getToken(torn),
          MockVault,
          approxVaultBalance,
        )
      })

      it('Should successfully distribute torn to default accounts', async function () {
        for (let i = 0; i < 3; i++) {
          await expect(() =>
            erc20Transfer(torn, tornWhale, signerArray[i].address, ethers.utils.parseEther('5000')),
          ).to.changeTokenBalance(await getToken(torn), signerArray[i], ethers.utils.parseEther('5000'))
        }
      })

      it('Accounts should successfully lock into governance', async () => {
        let gov = await ethers.getContractAt(
          'tornado-governance/contracts/Governance.sol:Governance',
          governance,
        )
        let Torn = await getToken(torn)

        for (let i = 0; i < 3; i++) {
          Torn = await Torn.connect(signerArray[i])
          await Torn.approve(gov.address, ethers.utils.parseEther('20000000'))
          gov = await gov.connect(signerArray[i])
          await expect(() => gov.lockWithApproval(ethers.utils.parseEther('5000'))).to.changeTokenBalance(
            Torn,
            signerArray[i],
            BigNumber.from(0).sub(ethers.utils.parseEther('5000')),
          )
        }
      })

      it('Should successfully imitate a dai whale', async function () {
        await sendr('hardhat_impersonateAccount', ['0x3890Fc235526C4e0691E042151c7a3a2d7b636D7'])
        daiWhale = await ethers.getSigner('0x3890Fc235526C4e0691E042151c7a3a2d7b636D7')
        await signerArray[0].sendTransaction({ to: daiWhale.address, value: ethers.utils.parseEther('1') })
      })
    })

    describe('Proposal passing', () => {
      it('Should successfully pass the proposal', async () => {
        const ProposalState = {
          Pending: 0,
          Active: 1,
          Defeated: 2,
          Timelocked: 3,
          AwaitingExecution: 4,
          Executed: 5,
          Expired: 6,
        }

        let response, id, state

        const gov = (
          await ethers.getContractAt('tornado-governance/contracts/Governance.sol:Governance', governance)
        ).connect(tornWhale)

        await (
          await (await getToken(torn)).connect(tornWhale)
        ).approve(gov.address, ethers.utils.parseEther('1000000'))

        await gov.lockWithApproval(ethers.utils.parseEther('26000'))

        response = await gov.propose(Proposal.address, 'Relayer Registry Proposal')
        id = await gov.latestProposalIds(tornWhale.address)
        state = await gov.state(id)

        const { events } = await response.wait()
        const args = events.find(({ event }) => event == 'ProposalCreated').args
        expect(args.id).to.be.equal(id)
        expect(args.proposer).to.be.equal(tornWhale.address)
        expect(args.target).to.be.equal(Proposal.address)
        expect(args.description).to.be.equal('Relayer Registry Proposal')
        expect(state).to.be.equal(ProposalState.Pending)

        await minewait((await gov.VOTING_DELAY()).add(1).toNumber())
        await expect(gov.castVote(id, true)).to.not.be.reverted
        state = await gov.state(id)
        expect(state).to.be.equal(ProposalState.Active)
        await minewait(
          (
            await gov.VOTING_PERIOD()
          )
            .add(await gov.EXECUTION_DELAY())
            .add(96400)
            .toNumber(),
        )
        state = await gov.state(id)
        console.log(state)

        await gov.execute(id)
      })
    })

    describe('Check params for deployed contracts', () => {
      it('Should assert params are correct', async function () {
        const globalData = await TornadoProxy.dataForTWAPOracle()

        expect(globalData[0]).to.equal(ethers.utils.parseUnits('1000', 'szabo'))
        expect(globalData[1]).to.equal(ethers.utils.parseUnits('5400', 'wei'))

        expect(await RelayerRegistry.minStakeAmount()).to.equal(ethers.utils.parseEther('100'))
        expect(await TornadoProxy.Registry()).to.equal(RelayerRegistry.address)
      })

      it('Should pass initial fee update', async () => {
        await TornadoProxy.updateAllFees()
      })
    })

    describe('Test registry registration', () => {
      it('Should successfully prepare a couple of relayer wallets', async function () {
        for (let i = 0; i < 4; i++) {
          const name = mainnet.project_specific.mocking.relayer_data[i][0]
          const address = mainnet.project_specific.mocking.relayer_data[i][1]
          const node = mainnet.project_specific.mocking.relayer_data[i][2]

          await sendr('hardhat_impersonateAccount', [address])

          relayers[i] = {
            node: node,
            ensName: name,
            address: address,
            wallet: await ethers.getSigner(address),
            subaddresses: [],
          }

          if (i == 2) relayers[i].subaddresses = [signerArray[4].address, signerArray[5].address]
          if (i == 0) relayers[i].subaddresses = [signerArray[8].address, signerArray[9].address]

          await expect(() =>
            signerArray[0].sendTransaction({ value: ethers.utils.parseEther('1'), to: relayers[i].address }),
          ).to.changeEtherBalance(relayers[i].wallet, ethers.utils.parseEther('1'))

          await expect(() =>
            erc20Transfer(torn, tornWhale, relayers[i].address, ethers.utils.parseEther('201')),
          ).to.changeTokenBalance(await getToken(torn), relayers[i].wallet, ethers.utils.parseEther('201'))
        }

        console.log(
          'Balance of whale after relayer funding: ',
          (await (await getToken(torn)).balanceOf(tornWhale.address)).toString(),
        )
      })

      it('Random account shouldnt be able to register if not owner of ens node', async () => {
        const gov = await Governance.connect(signerArray[0])
        await gov.unlock(ethers.utils.parseEther('200'))
        const registry = await RelayerRegistry.connect(signerArray[0])

        await expect(registry.register(relayers[0].node, ethers.utils.parseEther('200'), [])).to.be.reverted

        await gov.lockWithApproval(ethers.utils.parseEther('200'))
      })

      it('Should succesfully register all relayers', async function () {
        for (let i = 0; i < 4; i++) {
          ;(await getToken(torn))
            .connect(relayers[i].wallet)
            .approve(RelayerRegistry.address, ethers.utils.parseEther('300'))

          const registry = await RelayerRegistry.connect(relayers[i].wallet)

          await registry.register(relayers[i].node, ethers.utils.parseEther('101'), relayers[i].subaddresses)

          expect(await RelayerRegistry.isRelayerRegistered(relayers[i].address, relayers[i].address)).to.be
            .true
          expect(await RelayerRegistry.isRelayer(relayers[i].address)).to.be.true
          expect(await RelayerRegistry.getRelayerEnsHash(relayers[i].address)).to.equal(relayers[i].node)
        }
      })

      it('Register subaddress should work', async () => {
        await signerArray[6].sendTransaction({
          to: relayers[0].address,
          value: ethers.utils.parseEther('1'),
        })

        const registry = await RelayerRegistry.connect(relayers[0].wallet)
        await registry.registerWorker(relayers[0].address, signerArray[6].address)
        expect(await registry.isRelayerRegistered(relayers[0].address, signerArray[6].address)).to.be.true
        expect(await registry.isRelayerRegistered(relayers[0].address, signerArray[9].address)).to.be.true
      })

      it('Unregister should work', async () => {
        let registry = await RelayerRegistry.connect(signerArray[6])
        await registry.unregisterWorker(signerArray[6].address)
        expect(await registry.isRelayerRegistered(relayers[0].address, signerArray[6].address)).to.be.false

        registry = await RelayerRegistry.connect(signerArray[8])
        expect(await registry.isRelayerRegistered(relayers[0].address, signerArray[8].address)).to.be.true
        await registry.unregisterWorker(signerArray[8].address)
        expect(await registry.isRelayerRegistered(relayers[0].address, signerArray[8].address)).to.be.false
      })

      it('Random account shouldnt be able to unregister someone', async () => {
        const registry = await RelayerRegistry.connect(signerArray[0])
        await expect(registry.unregisterWorker(relayers[0].address)).to.be.reverted
      })
    })

    describe('Malicious registration', () => {
      it('Shouldnt be able to register address of another relayer', async () => {
        const registry = await RelayerRegistry.connect(relayers[0].wallet)

        await expect(registry.registerWorker(relayers[0].address, signerArray[4].address)).to.be.reverted
      })

      it('Shouldnt be able to steal address if registering again', async () => {
        const registry = await RelayerRegistry.connect(relayers[0].wallet)

        await expect(
          registry.register(relayers[0].node, ethers.utils.parseEther('100'), relayers[2].subaddresses),
        ).to.be.reverted
      })
    })

    describe('Malicious staking contract interaction', () => {
      it('Should not be able to call addBurnRewards if not registry', async () => {
        await expect(StakingContract.addBurnRewards(25)).to.be.reverted
      })

      it('Should not be able to call updateRewardsOnLockedBalanceChange if not gov', async () => {
        await expect(
          StakingContract.updateRewardsOnLockedBalanceChange(
            signerArray[0].address,
            ethers.utils.parseEther('10'),
          ),
        ).to.be.reverted
      })

      it('Should not be able to call rescueTokens if not gov', async () => {
        await expect(StakingContract.withdrawTorn(3556456456454)).to.be.reverted
      })
    })

    describe('Malicious depo/withdraw', () => {
      it('Relayer should not be able to withdraw and burn another relayer', async () => {
        const daiToken = await (await getToken(dai)).connect(daiWhale)
        const instanceAddress = tornadoPools[6]

        const initialShareValue = await StakingContract.accumulatedRewardPerTorn()
        const initialBalance = await RelayerRegistry.getRelayerBalance(relayers[0].address)

        const instance = await ethers.getContractAt(
          'tornado-anonymity-mining/contracts/interfaces/ITornadoInstance.sol:ITornadoInstance',
          instanceAddress,
        )
        const proxy = await TornadoProxy.connect(daiWhale)
        const mixer = (await ethers.getContractAt(MixerABI, instanceAddress)).connect(daiWhale)

        await daiToken.approve(TornadoProxy.address, ethers.utils.parseEther('1000000'))

        const depo = createDeposit({
          nullifier: rbigint(31),
          secret: rbigint(31),
        })

        await expect(() => proxy.deposit(instanceAddress, toHex(depo.commitment), [])).to.changeTokenBalance(
          daiToken,
          daiWhale,
          BigNumber.from(0).sub(await instance.denomination()),
        )

        let pevents = await mixer.queryFilter('Deposit')
        await initialize({ merkleTreeHeight: 20 })

        const { proof, args } = await generateProof({
          deposit: depo,
          recipient: daiWhale.address,
          relayerAddress: relayers[0].address,
          events: pevents,
        })

        const proxyWithRelayer = await proxy.connect(relayers[1].wallet)

        await expect(proxyWithRelayer.withdraw(instance.address, proof, ...args)).to.be.reverted

        expect(await RelayerRegistry.getRelayerBalance(relayers[0].address)).to.equal(initialBalance)
        expect(await StakingContract.accumulatedRewardPerTorn()).to.equal(initialShareValue)
      })
    })

    describe('Update rewards downgrades', () => {
      it('Should nullify balance of a relayer', async () => {
        const registry = await RelayerRegistry.connect(impGov)
        await registry.nullifyBalance(relayers[1].address)
        expect(await registry.getRelayerBalance(relayers[1].address)).to.equal(0)
      })

      it('Should not break logic by setting accumulated reward to 0, but let it revert and downgrade', async () => {
        let govtorn = (await getToken(torn)).connect(impGov)
        await govtorn.approve(StakingContract.address, ethers.utils.parseEther('20'))
        await govtorn.transfer(StakingContract.address, ethers.utils.parseEther('20'))

        let govstaking = await StakingContract.connect(impGov)
        await govstaking.addBurnRewards(ethers.utils.parseEther('20'))

        const snapshotId = await sendr('evm_snapshot', [])

        await StakingContract.getReward()

        await sendr('hardhat_setStorageAt', [
          StakingContract.address,
          '0x0',
          '0x0000000000000000000000000000000000000000000000000000000000000000',
        ])
        expect(await StakingContract.accumulatedRewardPerTorn()).to.equal(0)

        await expect(StakingContract.getReward()).to.be.reverted

        await expect(() => Governance.unlock(ethers.utils.parseEther('2'))).to.changeTokenBalance(
          await getToken(torn),
          signerArray[0],
          ethers.utils.parseEther('2'),
        )

        const response = await Governance.unlock(ethers.utils.parseEther('3'))

        const receipt = await response.wait()

        console.log('Event triggered: ', receipt.events[0].event)

        await expect(StakingContract.getReward()).to.be.reverted

        await sendr('evm_revert', [snapshotId])
      })
    })
  })

  after(async function () {
    await ethers.provider.send('hardhat_reset', [
      {
        forking: {
          jsonRpcUrl: `https://mainnet.infura.io/v3/${process.env.mainnet_rpc_key}`,
          blockNumber: process.env.use_latest_block == 'true' ? undefined : 13327013,
        },
      },
    ])
  })
})
