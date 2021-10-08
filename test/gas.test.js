const { ethers, upgrades } = require('hardhat')
const { expect } = require('chai')
const { mainnet } = require('./tests.data.json')
const { token_addresses } = mainnet
const { torn, dai } = token_addresses
const { BigNumber } = require('@ethersproject/bignumber')
const { rbigint, createDeposit, toHex, generateProof, initialize } = require('tornado-cli')
const MixerABI = require('tornado-cli/build/contracts/Mixer.abi.json')

describe('Data and Manager tests', () => {
  /// NAME HARDCODED
  let governance = mainnet.tornado_cash_addresses.governance

  let tornadoPools = mainnet.project_specific.contract_construction.RelayerRegistryData.tornado_pools
  let uniswapPoolFees = mainnet.project_specific.contract_construction.RelayerRegistryData.uniswap_pool_fees
  let poolTokens = mainnet.project_specific.contract_construction.RelayerRegistryData.pool_tokens
  // eslint-disable-next-line
  let denominations = mainnet.project_specific.contract_construction.RelayerRegistryData.pool_denominations

  let tornadoTrees = mainnet.tornado_cash_addresses.trees
  let tornadoProxy = mainnet.tornado_cash_addresses.tornado_proxy

  let approxVaultBalance = ethers.utils.parseUnits('13893131191552333230524', 'wei')

  //// LIBRARIES
  let OracleHelperLibrary
  let OracleHelperFactory

  //// CONTRACTS / FACTORIES
  let DataManagerFactory
  let DataManagerProxy

  let RegistryDataFactory
  let RegistryData

  let RelayerRegistry
  let RegistryFactory

  let ForwarderFactory
  let ForwarderContract

  let StakingFactory
  let StakingContract

  let TornadoInstances = []

  let TornadoProxyFactory
  let TornadoProxy

  let Governance

  let InstancesDataFactory
  let InstancesData

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

  // eslint-disable-next-line
  let erc20BalanceOf = async (tokenAddress, addressToCheck) => {
    const token = await getToken(tokenAddress)
    return await token.balanceOf(addressToCheck)
  }

  let minewait = async (time) => {
    await ethers.provider.send('evm_increaseTime', [time])
    await ethers.provider.send('evm_mine', [])
  }

  before(async function () {
    signerArray = await ethers.getSigners()

    OracleHelperFactory = await ethers.getContractFactory('UniswapV3OracleHelper')
    OracleHelperLibrary = await OracleHelperFactory.deploy()

    DataManagerFactory = await ethers.getContractFactory('RegistryDataManager', {
      libraries: {
        UniswapV3OracleHelper: OracleHelperLibrary.address,
      },
    })

    DataManagerProxy = await upgrades.deployProxy(DataManagerFactory, {
      unsafeAllow: ['external-library-linking'],
    })

    await upgrades.admin.changeProxyAdmin(DataManagerProxy.address, governance)

    RegistryDataFactory = await ethers.getContractFactory('RelayerRegistryData')

    RegistryData = await RegistryDataFactory.deploy(
      DataManagerProxy.address,
      governance,
      uniswapPoolFees,
      tornadoPools,
    )

    MockVaultFactory = await ethers.getContractFactory('TornadoVault')
    MockVault = await MockVaultFactory.deploy()

    StakingFactory = await ethers.getContractFactory('TornadoStakingRewards')
    StakingContract = await StakingFactory.deploy(governance, torn)

    RegistryFactory = await ethers.getContractFactory('RelayerRegistry')
    RelayerRegistry = await upgrades.deployProxy(RegistryFactory, {
      initializer: false,
    })

    ForwarderFactory = await ethers.getContractFactory('RegistryCallForwarder')
    ForwarderContract = await ForwarderFactory.deploy(governance, RelayerRegistry.address)

    await RelayerRegistry.initialize(
      RegistryData.address,
      ForwarderContract.address,
      StakingContract.address,
      torn,
    )

    await upgrades.admin.changeProxyAdmin(RelayerRegistry.address, governance)

    for (let i = 0; i < tornadoPools.length; i++) {
      const Instance = {
        isERC20: i > 3,
        token: token_addresses[poolTokens[i]],
        state: 2,
      }
      const Tornado = {
        addr: tornadoPools[i],
        instance: Instance,
      }
      TornadoInstances[i] = Tornado
    }

    TornadoProxyFactory = await ethers.getContractFactory('TornadoProxyRegistryUpgrade')
    TornadoProxy = await TornadoProxyFactory.deploy(
      RelayerRegistry.address,
      tornadoTrees,
      governance,
      TornadoInstances,
    )

    for (let i = 0; i < TornadoInstances.length; i++) {
      TornadoInstances[i].instance.state = 0
    }

    InstancesDataFactory = await ethers.getContractFactory('TornadoInstancesData')
    InstancesData = await InstancesDataFactory.deploy(TornadoInstances)

    GasCompensationFactory = await ethers.getContractFactory('GasCompensationVault')
    GasCompensation = await GasCompensationFactory.deploy()

    ////////////// PROPOSAL OPTION 1
    ProposalFactory = await ethers.getContractFactory('RelayerRegistryProposal')
    Proposal = await ProposalFactory.deploy(
      ForwarderContract.address,
      tornadoProxy,
      TornadoProxy.address,
      StakingContract.address,
      InstancesData.address,
      GasCompensation.address,
      MockVault.address,
    )

    Governance = await ethers.getContractAt('GovernanceStakingUpgrade', governance)
  })

  describe('Start of tests', () => {
    describe('Initialization related', () => {
      it('It should NOT be possible to call initialize again', async () => {
        await expect(
          RelayerRegistry.initialize(
            RegistryData.address,
            ForwarderContract.address,
            StakingContract.address,
            torn,
          ),
        ).to.be.reverted
      })
    })

    describe('Account setup procedure', () => {
      it('Should successfully imitate a torn whale', async function () {
        await sendr('hardhat_impersonateAccount', ['0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3'])
        tornWhale = await ethers.getSigner('0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3')
      })

      it('Should successfully imitate governance to transfer torn to vault,\n since we do this in the former proposal', async () => {
        await sendr('hardhat_impersonateAccount', [Governance.address])
        await sendr('hardhat_setBalance', [Governance.address, '0xDE0B6B3A7640000'])
        const impGov = await ethers.getSigner(Governance.address)
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
            erc20Transfer(torn, tornWhale, signerArray[i].address, ethers.utils.parseEther('5100')),
          ).to.changeTokenBalance(await getToken(torn), signerArray[i], ethers.utils.parseEther('5100'))
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
        const globalData = await RegistryData.dataForTWAPOracle()

        expect(globalData[0]).to.equal(ethers.utils.parseUnits('1000', 'szabo'))
        expect(globalData[1]).to.equal(ethers.utils.parseUnits('5400', 'wei'))

        expect(await RelayerRegistry.minStakeAmount()).to.equal(ethers.utils.parseEther('100'))
      })

      it('Should pass initial fee update', async () => {
        await RegistryData.updateAllFees()
      })

      it('Should repeatedly update fees and assure none return 0', async () => {
        let gasUsedForUpdateFees = BigNumber.from(0)

        for (let i = 0; i < tornadoPools.length; i++) {
          const response = await RegistryData.updateAllFees()
          const receipt = await response.wait()

          gasUsedForUpdateFees = gasUsedForUpdateFees.add(receipt.gasUsed)

          for (let j = 0; j < tornadoPools.length; j++) {
            expect(await RegistryData.getFeeForPoolId(i)).to.be.gt(0)
          }
        }

        gasUsedForUpdateFees = gasUsedForUpdateFees.div(tornadoPools.length)

        console.log('Gas used on average to update fees: ', gasUsedForUpdateFees.toString())
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
          }

          await expect(() =>
            signerArray[0].sendTransaction({ value: ethers.utils.parseEther('1'), to: relayers[i].address }),
          ).to.changeEtherBalance(relayers[i].wallet, ethers.utils.parseEther('1'))

          await expect(() =>
            erc20Transfer(torn, tornWhale, relayers[i].address, ethers.utils.parseEther('101')),
          ).to.changeTokenBalance(await getToken(torn), relayers[i].wallet, ethers.utils.parseEther('101'))
        }
      })

      it('Should succesfully register all relayers', async function () {
        let averageGasValue = BigNumber.from(0)

        for (let i = 0; i < 4; i++) {
          ;(await getToken(torn))
            .connect(relayers[i].wallet)
            .approve(RelayerRegistry.address, ethers.utils.parseEther('300'))

          const registry = await RelayerRegistry.connect(relayers[i].wallet)

          const response = await registry.register(relayers[i].node, ethers.utils.parseEther('101'), [])

          const receipt = await response.wait()

          averageGasValue = averageGasValue.add(receipt.gasUsed)

          expect(await RelayerRegistry.isRelayerRegistered(relayers[i].address, relayers[i].address)).to.be
            .true
        }

        averageGasValue = averageGasValue.div(4)

        console.log('Average gas used for registration: ', averageGasValue.toString())
      })
    })

    describe('Test deposit/withdrawals and reward updating', () => {
      let totalGasUsedForWithdrawal = BigNumber.from(0)

      it('Should succesfully deposit and withdraw from / into an instance', async function () {
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

        const proxyWithRelayer = await proxy.connect(relayers[0].wallet)

        const response = await proxyWithRelayer.withdraw(instance.address, proof, ...args)
        const receipt = await response.wait()

        totalGasUsedForWithdrawal = receipt.gasUsed

        expect(await RelayerRegistry.getRelayerBalance(relayers[0].address)).to.be.lt(initialBalance)
        expect(await StakingContract.accumulatedRewardPerTorn()).to.be.gt(initialShareValue)
      })

      it('Should calculate average gas usage for all lockWithApprovals(0)', async () => {
        let averageGasValue = BigNumber.from(0)

        for (let i = 0; i < 3; i++) {
          const gov = await Governance.connect(signerArray[0])
          const response = await expect(gov.lockWithApproval(100)).to.not.be.reverted
          const receipt = await response.wait()

          averageGasValue = averageGasValue.add(receipt.gasUsed)
        }

        averageGasValue = averageGasValue.div(3)

        console.log('Average gas used for locking: ', averageGasValue.toString())
      })

      it('Should succesfully deposit and withdraw from / into an instance', async function () {
        const daiToken = await (await getToken(dai)).connect(daiWhale)
        const instanceAddress = tornadoPools[6]

        const initialShareValue = await StakingContract.accumulatedRewardPerTorn()
        const initialBalance = await RelayerRegistry.getRelayerBalance(relayers[1].address)

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
          relayerAddress: relayers[1].address,
          events: pevents,
        })

        const proxyWithRelayer = await proxy.connect(relayers[1].wallet)

        const response = await proxyWithRelayer.withdraw(instance.address, proof, ...args)
        const receipt = await response.wait()

        totalGasUsedForWithdrawal = totalGasUsedForWithdrawal.add(receipt.gasUsed)
        totalGasUsedForWithdrawal = totalGasUsedForWithdrawal.div(2)

        expect(await RelayerRegistry.getRelayerBalance(relayers[1].address)).to.be.lt(initialBalance)
        expect(await StakingContract.accumulatedRewardPerTorn()).to.be.gt(initialShareValue)

        console.log('Average gas used for withdrawal: ', totalGasUsedForWithdrawal.toString())
      })

      it('Should calculate average gas usage for all unlock(0)', async () => {
        let averageGasValue = BigNumber.from(0)

        for (let i = 0; i < 3; i++) {
          const gov = await Governance.connect(signerArray[0])
          const response = await expect(gov.unlock(100)).to.not.be.reverted
          const receipt = await response.wait()

          averageGasValue = averageGasValue.add(receipt.gasUsed)
        }

        averageGasValue = averageGasValue.div(3)

        console.log('Average gas used for unlocking: ', averageGasValue.toString())
      })

      it('Should calculate average gas usage for getReward()', async () => {
        let gasUsedForClaimReward = BigNumber.from(0)

        for (let i = 0; i < 3; i++) {
          const staking = await StakingContract.connect(signerArray[i])
          const response = await staking.getReward()
          const receipt = await response.wait()
          gasUsedForClaimReward = gasUsedForClaimReward.add(receipt.gasUsed)
        }

        gasUsedForClaimReward = gasUsedForClaimReward.div(3)

        console.log('Average gas used for getReward(): ', gasUsedForClaimReward.toString())
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
