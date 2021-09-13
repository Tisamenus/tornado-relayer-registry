const { ethers, upgrades } = require('hardhat')
const { BigNumber } = require('@ethersproject/bignumber')
const { expect } = require('chai')

describe('Data and Manager tests', () => {
  /// HARDCODED
  let torn = '0x77777FeDdddFfC19Ff86DB637967013e6C6A116C'
  let governance = '0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce'
  let weth = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
  let dai = '0x6B175474E89094C44Da98b954EedeAC495271d0F'

  //// LIBRARIES
  let OracleHelperLibrary
  let OracleHelperFactory

  //// CONTRACTS / FACTORIES
  let DataManagerFactory
  let DataManagerProxy

  let RegistryDataFactory
  let RegistryData

  //// IMPERSONATED ACCOUNTS
  let impGov;

  //// NORMAL ACCOUNTS
  let signerArray

  //// HELPER FN
  let sendr = async (method, params) => {
    return await ethers.provider.send(method, params)
  }

  before(async () => {
    signerArray = await ethers.getSigners();

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
      [0, 0, 0, 0, 3000, 3000, 3000, 3000],
      [
        '0x12d66f87a04a9e220743712ce6d9bb1b5616b8fc',
        '0x47ce0c6ed5b0ce3d3a51fdb1c52dc66a7c3c2936',
        '0x910cbd523d972eb0a6f4cae4618ad62622b39dbf',
        '0xa160cdab225685da1d56aa342ad8841c3b53f291',
        '0xd4b88df4d29f5cedd6857912842cff3b20c8cfa3',
        '0xfd8610d20aa15b7b2e3be39b396a1bc3516c7144',
        '0x07687e702b410fa43f4cb4af7fa097918ffd2730',
        '0x23773e65ed146a459791799d01336db287f25334',
      ],
    )
  })

  describe('Start of tests', () => {

    describe('Setup procedure', () => {
      it('Should have properly initialized all data', async () => {
        for (i = 0; i < 8; i++) {
          console.log(await RegistryData.getPoolDataForPoolId(i))
        }
      })

      it('Should impersonate governance properly', async () => {
        await sendr('hardhat_impersonateAccount', [governance])
        impGov = await ethers.getSigner(governance)
	await sendr('hardhat_setBalance', [governance, "0xDE0B6B3A7640000"])
      });

      it('Should set RegistryData global params', async () => {
	regData = await RegistryData.connect(impGov);
	await regData.setProtocolPeriod(ethers.utils.parseUnits("5400", "wei"));
	await regData.setProtocolFee(ethers.utils.parseUnits("10", "finney"));
      });

      it('Should pass initial fee update', async () => {
	await RegistryData.updateFees();
        for (i = 0; i < 8; i++) {
          console.log(await RegistryData.getFeeForPoolId(i))
        }
      });
    })

  })
})
