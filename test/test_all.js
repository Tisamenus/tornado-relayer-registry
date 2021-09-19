const { ethers, upgrades } = require('hardhat')
const { expect } = require('chai')
const { mainnet } = require('./tests.data.json')
const { token_addresses } = mainnet
const { torn, dai } = token_addresses

describe('Data and Manager tests', () => {
  /// NAME HARDCODED
  let governance = mainnet.tornado_cash_addresses.governance
  let tornadoPools = mainnet.project_specific.contract_construction.RelayerRegistryData.tornado_pools
  let uniswapPoolFees = mainnet.project_specific.contract_construction.RelayerRegistryData.uniswap_pool_fees
  let tornadoTrees = mainnet.tornado_cash_addresses.trees
  let tornadoProxy = mainnet.tornado_cash_addresses.tornado_proxy

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

  let StakingFactory
  let StakingContract

  let TornadoInstances = []

  let TornadoProxyFactory
  let TornadoProxy

  //// IMPERSONATED ACCOUNTS
  let tornWhale

  //// NORMAL ACCOUNTS
  let signerArray

  //// HELPER FN
  let sendr = async (method, params) => {
    return await ethers.provider.send(method, params)
  }

  let getToken = async (tokenAddress) => {
    return await ethers.getContractAt('@openzeppelin/0.6.x/token/ERC20/IERC20.sol:IERC20', tokenAddress)
  }

  let erc20Transfer = async (tokenAddress, senderWallet, recipientAddress, amount) => {
    const token = (await getToken(tokenAddress)).connect(senderWallet)
    return await token.transfer(recipientAddress, amount)
  }

  let minewait = async (time) => {
    await ethers.provider.send('evm_increaseTime', [time])
    await ethers.provider.send('evm_mine', [])
  }

  before(async () => {
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

    StakingFactory = await ethers.getContractFactory('TornadoStakingRewards')

    StakingContract = await StakingFactory.deploy(governance, torn, ethers.utils.parseUnits('13893131191552333230524', "wei"))

    RegistryFactory = await ethers.getContractFactory('RelayerRegistry')

    RelayerRegistry = await RegistryFactory.deploy(RegistryData.address, governance, StakingContract.address)

    for (i = 0; i < tornadoPools.length; i++) {
      const Instance = {
        isERC20: i > 3,
        token: i < 4 ? '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE' : dai,
        state: 1,
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

    ////////////// PROPOSAL OPTION 1
    ProposalFactory = await ethers.getContractFactory('RelayerRegistryProposalOption1')
    Proposal = await ProposalFactory.deploy(
      RelayerRegistry.address,
      tornadoProxy,
      TornadoProxy.address,
      StakingContract.address,
    )
  })

  describe('Start of tests', () => {
    describe('Account setup procedure', async () => {
      it('Should successfully imitate a torn whale', async () => {
        await sendr('hardhat_impersonateAccount', ['0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3'])
        tornWhale = await ethers.getSigner('0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3')
      })
    })

    describe('Proposal passing', async () => {
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

	const gov = (await ethers.getContractAt("tornado-governance/contracts/Governance.sol:Governance", governance)).connect(tornWhale)

	await (await (await getToken(torn)).connect(tornWhale)).approve(gov.address, ethers.utils.parseEther("1000000"))

	await gov.lockWithApproval(ethers.utils.parseEther("40000"))

	response = await gov.propose(Proposal.address, "Relayer Registry Proposal")
	id = await gov.latestProposalIds(tornWhale.address)
	state = await gov.state(id)

        const { events } = await response.wait()
        const args = events.find(({ event }) => event == 'ProposalCreated').args
        expect(args.id).to.be.equal(id)
        expect(args.proposer).to.be.equal(tornWhale.address)
        expect(args.target).to.be.equal(Proposal.address)
        expect(args.description).to.be.equal("Relayer Registry Proposal")
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
      it('Should assert params are correct', async () => {
	const globalData = await RegistryData.protocolPoolData()
	expect(globalData[0]).to.equal(ethers.utils.parseUnits("1000", "szabo"))
	expect(globalData[1]).to.equal(ethers.utils.parseUnits("5400", "wei"))

	expect(await TornadoStakingRewards.distributionPeriod()).to.equal(ethers.utils.parseUnits("86400", "wei").mul(BigNumber.from(365)))
	expect(await RelayerRegistry.minStakeAmount()).to.equal(ethers.utils.parseEther("20"))
      })

      it('Should pass initial fee update', async () => {
        await RegistryData.updateFees()
        for (i = 0; i < 8; i++) {
          const poolName = i <= 3 ? 'eth' : 'dai'
          const constant = i <= 3 ? 0.1 : 100
          console.log(
            `${poolName}-${constant * 10 ** (i % 4)}-pool fee: `,
            (await RegistryData.getFeeForPoolId(i)).div(ethers.utils.parseUnits('1', 'szabo')).toNumber() /
              1000000,
            `torn`,
          )
        }
      })
    })

    describe('Test registry registration', () => {
      let relayers = []

      it('Should successfully prepare a couple of relayer wallets', async () => {
        for (i = 0; i < 4; i++) {
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

        console.log(
          'Balance of whale after relayer funding: ',
          (await (await getToken(torn)).balanceOf(tornWhale.address)).toString(),
        )
      })

      it('Should succesfully register all relayers', async () => {
        const metadata = { isRegistered: true, fee: ethers.utils.parseEther('0.1') }

        for (i = 0; i < 4; i++) {
          ;(await getToken(torn))
            .connect(relayers[i].wallet)
            .approve(StakingContract.address, ethers.utils.parseEther('300'))

          const registry = await RelayerRegistry.connect(relayers[i].wallet)

          await registry.register(relayers[i].node, ethers.utils.parseEther('101'), metadata)

          console.log(
            'Share price: ',
            (await StakingContract.currentSharePrice()).toString(),
            ', staked amount: ',
            (await StakingContract.stakedAmount()).toString(),
          )

          expect(await RelayerRegistry.isRelayerRegistered(relayers[i].node)).to.be.true
          expect(await RelayerRegistry.getRelayerFee(relayers[i].node)).to.equal(metadata.fee)
        }
      })
    })
  })
})
