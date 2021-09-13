const { ethers } = require('hardhat')
const { BigNumber } = require('@ethersproject/bignumber')
const { expect } = require('chai')

describe('Uniswap V3 Price Tests', () => {
  /// HARDCODED
  let torn = '0x77777FeDdddFfC19Ff86DB637967013e6C6A116C'
  let usdc = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'

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
      await expect(PriceContract.getPriceOfTokenInETH(torn, 10000, 5400)).to.not.be.reverted

      const priceOfTORNInETH = await PriceContract.lastPriceOfToken(torn)

      console.log(priceOfTORNInETH.toString())
    })

    it('Should fetch a uniswap v3 price for USDC per TORN', async () => {
      await expect(PriceContract.getPriceOfTokenInToken([torn, usdc], [10000, 10000], 5400)).to.not.be
        .reverted

      const priceOfTORNInUSDC = await PriceContract.lastPriceOfATokenInToken()

      console.log(priceOfTORNInUSDC.toString())
    })

    it('Should fetch a uniswap v3 price for TORN per ETH', async () => {
      await expect(PriceContract.getPriceOfWETHInToken(torn, 10000, 5400)).to.not.be.reverted

      const priceOfETHInTORN = await PriceContract.lastPriceOfToken(torn)

      console.log(priceOfETHInTORN.toString())
    })
  })
})
