require('dotenv').config()
require('@nomiclabs/hardhat-ethers')
require('@nomiclabs/hardhat-etherscan')
require('@nomiclabs/hardhat-waffle')
require('hardhat-spdx-license-identifier')
require('hardhat-storage-layout')
require('hardhat-log-remover')
require('hardhat-contract-sizer')
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
        },
      },
      {
        version: '0.8.7',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.mainnet_rpc,
        blockNumber: 13211966,
      },
      initialBaseFeePerGas: 5,
      loggingEnabled: true,
      allowUnlimitedContractSize: false,
    },
    localhost: {
      url: 'http://localhost:8545',
      timeout: 120000,
    },
    mainnet: {
      url: process.env.mainnet_rpc,
      accounts: [process.env.mainnet_account_pk],
      timeout: 2147483647,
    },
    goerli: {
      url: process.env.goerli_rpc,
      accounts: [process.env.goerli_account_pk],
      timeout: 2147483647,
    },
  },
  mocha: { timeout: 9999999999 },
  spdxLicenseIdentifier: {
    overwrite: true,
    runOnCompile: true,
  },
  etherscan: {
    apiKey: process.env.etherscan_api_key,
  },
}
