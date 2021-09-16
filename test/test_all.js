const { ethers, upgrades } = require('hardhat')
const { expect } = require('chai')
const { mainnet } = require('./tests.data.json')
const { token_addresses } = mainnet
const { torn } = token_addresses
const { namehash } = require('@ethersproject/hash')
const { BigNumber } = require('@ethersproject/bignumber')

describe('Data and Manager tests', () => {
  /// NAME HARDCODED
  let governance = mainnet.tornado_cash_addresses.governance
  let tornadoPools = mainnet.project_specific.contract_construction.RelayerRegistryData.tornado_pools
  let uniswapPoolFees = mainnet.project_specific.contract_construction.RelayerRegistryData.uniswap_pool_fees

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

  //// IMPERSONATED ACCOUNTS
  let impGov
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

    StakingContract = await StakingFactory.deploy(governance, torn, ethers.utils.parseEther('20'))

    RegistryFactory = await ethers.getContractFactory('RelayerRegistry')

    RelayerRegistry = await RegistryFactory.deploy(
      RegistryData.address,
      governance,
      torn,
      DataManagerProxy.address,
      StakingContract.address,
    )
  })

  describe('Start of tests', () => {
    describe('Setup procedure Manager and RegistryData', () => {
      it('Should impersonate governance properly', async () => {
        await sendr('hardhat_impersonateAccount', [governance])
        impGov = await ethers.getSigner(governance)
        await sendr('hardhat_setBalance', [governance, '0xDE0B6B3A7640000'])
      })

      it('Should set RegistryData global params', async () => {
        regData = await RegistryData.connect(impGov)
        await regData.setProtocolPeriod(ethers.utils.parseUnits('1000', 'wei'))
        await regData.setProtocolFee(ethers.utils.parseUnits('1000', 'szabo'))
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

      it('Should setup StakingRewards', async () => {
        const staking = await StakingContract.connect(impGov)
        await staking.setDistributionPeriod(6 * 3600)
        expect(await StakingContract.distributionPeriod()).to.equal(6 * 3600)
      })
    })

    describe('Setup procedure RelayerRegistry', () => {
      it('Should have deployed Registry with proper data', async () => {
        expect(await RelayerRegistry.governance()).to.equal(governance)
        expect(await RelayerRegistry.tornadoProxy()).to.equal(DataManagerProxy.address)
        expect(await RelayerRegistry.torn()).to.equal(torn)
      })

      it('Should set min stake amount to 100 TORN', async () => {
        const relReg = await RelayerRegistry.connect(impGov)
        await relReg.setMinStakeAmount(ethers.utils.parseEther('100'))
        expect(await relReg.minStakeAmount()).to.equal(ethers.utils.parseEther('100'))
      })

      it('Should successfully imitate a torn whale', async () => {
        await sendr('hardhat_impersonateAccount', ['0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3'])
        tornWhale = await ethers.getSigner('0xA2b2fBCaC668d86265C45f62dA80aAf3Fd1dEde3')
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
