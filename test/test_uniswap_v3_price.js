const { ethers } = require('hardhat')
const { expect } = require('chai')
const { mainnet } = require("./tests.data.json");
const { token_addresses } = mainnet;
const {torn, usdc} = token_addresses;

describe('Uniswap V3 Price Tests', () => {
  //// LIBRARIES
  let PriceHelperLibrary
  let PriceHelperFactory

  //// CONTRACTS / FACTORIES
  let PriceContract
  let PriceFactory

  //// HELPER FN

  before(async () => {
    PriceHelperFactory = await ethers.getContractFactory('UniswapV3OracleHelper')
    PriceHelperLibrary = await PriceHelperFactory.deploy()

    PriceFactory = await ethers.getContractFactory('PriceTester', {
      libraries: {
        UniswapV3OracleHelper: PriceHelperLibrary.address,
      },
    })
    PriceContract = await PriceFactory.deploy()
  })

  describe('Start of tests', () => {
    it('Should fetch a uniswap v3 price for ETH per TORN', async () => {
      await expect(PriceContract.getPriceOfTokenInETH(torn, 10000, 1000)).to.not.be.reverted

      const priceOfTORNInETH = await PriceContract.lastPriceOfToken(torn)

      console.log(priceOfTORNInETH.toString())
    })

    it('Should fetch a uniswap v3 price for USDC per TORN', async () => {
      await expect(PriceContract.getPriceOfTokenInToken([torn, usdc], [10000, 10000], 1000)).to.not.be
        .reverted

      const priceOfTORNInUSDC = await PriceContract.lastPriceOfATokenInToken()

      console.log(priceOfTORNInUSDC.toString())
    })

    it('Should fetch a uniswap v3 price for TORN per ETH', async () => {
      await expect(PriceContract.getPriceOfWETHInToken(torn, 10000, 1000)).to.not.be.reverted

      const priceOfETHInTORN = await PriceContract.lastPriceOfToken(torn)

      console.log(priceOfETHInTORN.toString())
    })
  })
})
