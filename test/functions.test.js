const { ethers } = require('hardhat')
const { expect } = require('chai')
const { mainnet } = require('./tests.data.json')
const { token_addresses } = mainnet
const { torn, dai } = token_addresses
const { BigNumber } = require('@ethersproject/bignumber')
const { rbigint, createDeposit, toHex, generateProof, initialize } = require('tornado-cli')
const MixerABI = require('tornado-cli/build/contracts/Mixer.abi.json')

describe('General functionality tests', () => {
  /// NAME HARDCODED
  let governance = mainnet.tornado_cash_addresses.governance
  const instancePath = 'tornado-anonymity-mining/contracts/interfaces/ITornadoInstance.sol:ITornadoInstance'

  let tornadoPools = mainnet.project_specific.contract_construction.RelayerRegistryData.tornado_pools
  let uniswapPoolFees = mainnet.project_specific.contract_construction.RelayerRegistryData.uniswap_pool_fees
  let poolTokens = mainnet.project_specific.contract_construction.RelayerRegistryData.pool_tokens
  let denominations = mainnet.project_specific.contract_construction.RelayerRegistryData.pool_denominations
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

  let DataManagerFactory
  let DataManagerProxy
  let DataManager

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

    /// CREATE2 CONTRACTS
    SingletonFactory = await ethers.getContractAt('SingletonFactory', singletonFactoryAddress)
    Create2ComputerFactory = await ethers.getContractFactory('Create2Computer')
    Create2Computer = await Create2ComputerFactory.deploy()

    //// PROXY DEPLOYMENTS
    DataManagerFactory = await ethers.getContractFactory('RegistryDataManager')
    ProxyFactory = await ethers.getContractFactory('AdminUpgradeableProxy')

    //// READ IN
    MockVaultFactory = await ethers.getContractFactory('TornadoVault')
    MockVault = await MockVaultFactory.deploy()

    //// POOL DATA

    for (let i = 0; i < tornadoPools.length; i++) {
      const PoolData = {
        uniPoolFee: uniswapPoolFees[i],
        poolFee: feesArray[i],
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
    await SingletonFactory.deploy(DataManagerFactory.bytecode, salt)
    const deploymentAddressManager = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(DataManagerFactory.bytecode),
      SingletonFactory.address,
    )

    DataManager = await ethers.getContractAt('RegistryDataManager', deploymentAddressManager)

    /////////////// DATA MANAGER PROXY
    const proxyDeploymentBytecode =
      ProxyFactory.bytecode +
      ProxyFactory.interface.encodeDeploy([DataManager.address, governance, []]).slice(2)

    await SingletonFactory.deploy(proxyDeploymentBytecode, salt)

    const deploymentAddressManagerProxy = await Create2Computer.computeAddress(
      salt,
      ethers.utils.keccak256(proxyDeploymentBytecode),
      SingletonFactory.address,
    )

    DataManagerProxy = await ethers.getContractAt('RegistryDataManager', deploymentAddressManagerProxy)

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
          DataManagerProxy.address,
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
    console.log('Exp. addr. DataManager: ', deploymentAddressManager)
    //////////////////////////////////////////////////////////////////////////////////////////

    GasCompensationFactory = await ethers.getContractFactory('GasCompensationVault')
    GasCompensation = await GasCompensationFactory.deploy()

    ////////////// PROPOSAL OPTION 1
    ProposalFactory = await ethers.getContractFactory('RelayerRegistryProposal')
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

        for (let i = 0; i < TornadoInstances.length - 1; i++) {
          expect(await TornadoProxy.getPoolToken(TornadoInstances[i].addr)).to.equal(
            TornadoInstances[i].instance.token,
          )
        }
      })

      it('Should pass initial fee update', async () => {
        await TornadoProxy.updateAllFees()
        for (let i = 0; i < tornadoPools.length - 1; i++) {
          console.log(
            `${poolTokens[i]}-${denominations[i]}-pool fee: `,
            (await TornadoProxy.getFeeForPoolId(i)).div(ethers.utils.parseUnits('1', 'szabo')).toNumber() /
              1000000,
            'torn',
          )
        }
      })

      it('Should repeatedly update fees and assure none return 0', async () => {
        for (let i = 0; i < tornadoPools.length - 1; i++) {
          await TornadoProxy.updateAllFees()
          for (let j = 0; j < tornadoPools.length - 1; j++) {
            expect(await TornadoProxy.getFeeForPoolId(j)).to.be.gt(0)
          }
        }
      })

      it('Should test repeatedly updating fees of specific pool and assure none return 0', async () => {
        for (let i = 0; i < tornadoPools.length - 1; i++) {
          await TornadoProxy.updateFeeOfPool(i)
          expect(await TornadoProxy.getFeeForPoolId(i)).to.be.gt(0)
        }
      })

      it('Update fees of all pools and partial should work too', async () => {
        let poolIdsAll = []
        let poolIdsSome = []

        for (let i = 0; i < tornadoPools.length - 1; i++) {
          poolIdsAll.push(i)
          if (i % 2) poolIdsSome.push(i)
        }

        await TornadoProxy.updateFeesOfPools(poolIdsAll)

        for (let i = 0; i < tornadoPools.length - 1; i++) {
          expect(await TornadoProxy.getFeeForPoolId(i)).to.be.gt(0)
        }

        await TornadoProxy.updateFeesOfPools(poolIdsSome)

        for (let i = 0; i < tornadoPools.length - 1; i++) {
          expect(await TornadoProxy.getFeeForPoolId(i)).to.be.gt(0)
        }
      })

      it('Should be able to add a pool and update its fees and print', async () => {
        const proxygov = await TornadoProxy.connect(impGov)
        let index = tornadoPools.length - 1

        let newInstance = TornadoInstances[index]

        await proxygov.updateInstance(newInstance)

        await proxygov.updateFeeOfPool(index)

        console.log(
          `${poolTokens[index]}-${denominations[index]}-pool fee:`,
          (await TornadoProxy.getFeeForPoolId(index)).div(ethers.utils.parseUnits('1', 'szabo')).toNumber() /
            1000000,
          'torn',
        )

        await proxygov.updateAllFees()
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
            erc20Transfer(torn, tornWhale, relayers[i].address, ethers.utils.parseEther('101')),
          ).to.changeTokenBalance(await getToken(torn), relayers[i].wallet, ethers.utils.parseEther('101'))
        }

        console.log(
          'Balance of whale after relayer funding: ',
          (await (await getToken(torn)).balanceOf(tornWhale.address)).toString(),
        )
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
    })

    describe('Test deposit/withdrawals and reward updating', () => {
      it('Should succesfully deposit and withdraw from / into an instance', async function () {
        const daiToken = await (await getToken(dai)).connect(daiWhale)
        const instanceAddress = tornadoPools[6]

        const initialShareValue = await StakingContract.accumulatedRewardPerTorn()
        const initialBalance = await RelayerRegistry.getRelayerBalance(relayers[0].address)

        const instance = await ethers.getContractAt(instancePath, instanceAddress)
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

        await expect(() => proxyWithRelayer.withdraw(instance.address, proof, ...args)).to.changeTokenBalance(
          daiToken,
          daiWhale,
          await instance.denomination(),
        )

        expect(await RelayerRegistry.getRelayerBalance(relayers[0].address)).to.be.lt(initialBalance)
        expect(await StakingContract.accumulatedRewardPerTorn()).to.be.gt(initialShareValue)
      })

      it('Should call a lockWithApproval(0) for a signer and have incremented some of his rewards', async () => {
        const gov = await Governance.connect(signerArray[0])
        await expect(gov.lockWithApproval(0)).to.not.be.reverted

        const balance = await StakingContract.accumulatedRewards(signerArray[0].address)
        expect(balance).to.be.gt(0)

        console.log('Signer 0 accumulatedRewards: ', balance.toString())
      })

      it('Should test governance balance nullification', async () => {
        const registry = await RelayerRegistry.connect(impGov)
        await registry.nullifyBalance(relayers[0].address)
        expect(await registry.getRelayerBalance(relayers[0].address)).to.equal(0)
      })

      it('This time around relayer should not have enough funds for withdrawal', async function () {
        const daiToken = await (await getToken(dai)).connect(daiWhale)
        const instanceAddress = tornadoPools[6]

        const initialBalance = await RelayerRegistry.getRelayerBalance(relayers[0].address)

        const instance = await ethers.getContractAt(instancePath, instanceAddress)
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

        const result1 = await generateProof({
          deposit: depo,
          recipient: daiWhale.address,
          relayerAddress: relayers[0].address,
          events: pevents,
        })

        const proxyWithRelayer = await proxy.connect(relayers[0].wallet)

        await expect(proxyWithRelayer.withdraw(instance.address, result1.proof, ...result1.args)).to.be
          .reverted

        expect(await RelayerRegistry.getRelayerBalance(relayers[0].address)).to.equal(initialBalance)

        const result2 = await generateProof({
          deposit: depo,
          recipient: daiWhale.address,
          events: pevents,
        })

        await expect(() =>
          proxy.withdraw(instance.address, result2.proof, ...result2.args),
        ).to.changeTokenBalance(daiToken, daiWhale, await instance.denomination())
      })
    })

    describe('Test claiming rewards multiple times and withdrawing from gov', () => {
      it('Should NOT reward you if you lock, then try to harvest', async () => {
        const k5 = ethers.utils.parseEther('5000')

        await expect(() => erc20Transfer(torn, tornWhale, signerArray[3].address, k5)).to.changeTokenBalance(
          await getToken(torn),
          signerArray[3],
          k5,
        )

        const gov = await Governance.connect(signerArray[3])
        const Torn = (await getToken(torn)).connect(signerArray[3])
        const staking = await StakingContract.connect(signerArray[3])

        await Torn.approve(gov.address, k5)
        await gov.lockWithApproval(k5)
        await staking.getReward()

        const balance = await gov.lockedBalance(signerArray[3].address)

        expect(balance).to.equal(k5)
      })

      it('Should properly harvest rewards if someone calls getReward', async function () {
        const Torn = await getToken(torn)

        const initialBalance0 = await Torn.balanceOf(signerArray[0].address)
        const initialBalance1 = await Torn.balanceOf(signerArray[2].address)

        let staking = await StakingContract.connect(signerArray[0])
        await staking.getReward()
        staking = await StakingContract.connect(signerArray[2])
        await staking.getReward()

        expect(await Governance.lockedBalance(signerArray[0].address)).to.be.gt(initialBalance0)
        expect(await Governance.lockedBalance(signerArray[2].address)).to.be.gt(initialBalance1)
      })

      it('Second harvest shouldnt work if no withdraw was made', async () => {
        const Torn = await getToken(torn)

        const initialBalance0 = await Torn.balanceOf(signerArray[0].address)
        const initialBalance1 = await Torn.balanceOf(signerArray[2].address)

        let staking = await StakingContract.connect(signerArray[0])
        await staking.getReward()
        staking = await StakingContract.connect(signerArray[2])
        await staking.getReward()

        expect(await Torn.balanceOf(signerArray[0].address)).to.be.equal(initialBalance0)
        expect(await Torn.balanceOf(signerArray[2].address)).to.be.equal(initialBalance1)
      })

      it('It should NOT be possible to withdraw more than you have', async () => {
        let gov = await Governance.connect(signerArray[0])
        await expect(gov.unlock(ethers.utils.parseEther('5000000'))).to.be.reverted
      })
    })

    describe('Test staking to relayer', () => {
      it('Should be able to withdraw some torn from governance and stake to a relayer', async () => {
        const gov = await Governance.connect(signerArray[0])
        const k1 = ethers.utils.parseEther('100')
        const Torn = (await getToken(torn)).connect(signerArray[0])

        await expect(() => gov.unlock(k1)).to.changeTokenBalance(await getToken(torn), signerArray[0], k1)

        const registry = await RelayerRegistry.connect(signerArray[0])

        await Torn.approve(RelayerRegistry.address, k1)

        await registry.stakeToRelayer(relayers[0].address, k1)

        expect(await registry.getRelayerBalance(relayers[0].address)).to.equal(k1)
      })

      it('Should succesfully deposit and withdraw from / into the instance we staked to', async function () {
        const daiToken = await (await getToken(dai)).connect(daiWhale)
        const instanceAddress = tornadoPools[6]

        const initialShareValue = await StakingContract.accumulatedRewardPerTorn()
        const initialBalance = await RelayerRegistry.getRelayerBalance(relayers[0].address)

        const instance = await ethers.getContractAt(instancePath, instanceAddress)
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

        const proxyWithRelayer = await proxy.connect(signerArray[9])

        await expect(() => proxyWithRelayer.withdraw(instance.address, proof, ...args)).to.changeTokenBalance(
          daiToken,
          daiWhale,
          await instance.denomination(),
        )

        expect(await RelayerRegistry.getRelayerBalance(signerArray[9].address)).to.be.lt(initialBalance)
        expect(await StakingContract.accumulatedRewardPerTorn()).to.be.gt(initialShareValue)
      })

      it('Signer at index 1 should have largest accumulatedRewards and 2 > 0', async () => {
        for (let i = 0; i < 3; i++) {
          const gov = await Governance.connect(signerArray[i])
          await gov.unlock(0)
        }
        const balanceS1 = await StakingContract.accumulatedRewards(signerArray[1].address)
        const balanceS2 = await StakingContract.accumulatedRewards(signerArray[2].address)
        const balanceS0 = await StakingContract.accumulatedRewards(signerArray[0].address)

        expect(balanceS2).to.be.gt(balanceS0)
        expect(balanceS1).to.be.gt(balanceS2)

        console.log('Signer 0 accumulatedRewards: ', balanceS0.toString())
        console.log('Signer 1 accumulatedRewards: ', balanceS1.toString())
        console.log('Signer 2 accumulatedRewards: ', balanceS2.toString())
      })

      it('Should harvest those rewards again', async () => {
        for (let i = 0; i < 3; i++) {
          const initBalance = await erc20BalanceOf(torn, signerArray[i].address)
          const staking = await StakingContract.connect(signerArray[i])
          await staking.getReward()
          expect(await erc20BalanceOf(torn, signerArray[i].address)).to.be.gt(initBalance)
        }
      })
    })

    describe('Test governance interaction', () => {
      it('Should nullify relayers balance', async () => {
        const registry = await RelayerRegistry.connect(impGov)
        await registry.nullifyBalance(relayers[3].address)

        const balance = await RelayerRegistry.getRelayerBalance(relayers[3].address)

        expect(balance).to.eq(0)
      })

      it('Should harvest those rewards again', async () => {
        for (let i = 0; i < 3; i++) {
          const initBalance = await erc20BalanceOf(torn, signerArray[i].address)
          const staking = await StakingContract.connect(signerArray[i])
          await staking.getReward()
          expect(await erc20BalanceOf(torn, signerArray[i].address)).to.be.gt(initBalance)
        }
      })

      it('Governance should be able to save some tokens', async () => {
        let snapshot = await sendr('evm_snapshot', [])

        const hundred = ethers.utils.parseEther('100')
        const tornToken = (await getToken(torn)).connect(tornWhale)
        await tornToken.transfer(StakingContract.address, hundred)

        // gov to rescue
        const staking = await StakingContract.connect(impGov)
        await expect(() => staking.rescueTokens(hundred)).to.changeTokenBalance(
          await getToken(torn),
          Governance,
          hundred,
        )

        await sendr('evm_revert', [snapshot])
        snapshot = await sendr('evm_snapshot', [])

        await tornToken.transfer(StakingContract.address, hundred)

        const initialBalance = await tornToken.balanceOf(StakingContract.address)

        await expect(() => staking.rescueTokens(ethers.constants.MaxUint256)).to.changeTokenBalance(
          await getToken(torn),
          Governance,
          initialBalance,
        )

        await sendr('evm_revert', [snapshot])
      })

      it('Governance should be able to add rewards', async () => {
        const registry = await RelayerRegistry.connect(impGov)
        const tornToken = (await getToken(torn)).connect(impGov)

        await tornToken.approve(registry.address, ethers.utils.parseEther('100'))
        await expect(() => registry.addRewards(ethers.utils.parseEther('100'))).to.changeTokenBalance(
          tornToken,
          StakingContract,
          ethers.utils.parseEther('100'),
        )
      })

      it('Should harvest those rewards again', async () => {
        for (let i = 0; i < 3; i++) {
          const initBalance = await erc20BalanceOf(torn, signerArray[i].address)
          const staking = await StakingContract.connect(signerArray[i])
          await staking.getReward()
          expect(await erc20BalanceOf(torn, signerArray[i].address)).to.be.gt(initBalance)
        }
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
