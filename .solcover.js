module.exports = {
  skipFiles: [
    'mock/CompileDummy.sol', // mock
    'mock/CompileDummy2.sol', // mock
    'mock/PriceTester.sol', // mock
    'RelayerRegistryProposal.sol', // because MockProposal.sol is being tested, coverage adds bytecode so create2 checks have to differ
    'utils/SingletonFactory.sol', // this was added as an EIP and is thus trusted
    // --------------------------------------
    // the below are ignored due to solcover not recognizing coverage with these files and
    // spitting out false coverage reports for some reason

    'staking/TornadoStakingRewards.sol',
    'tornado-proxy/TornadoProxyRegistryUpgrade.sol',

    // ModifiedTornadoProxy.sol
    // although the proxy is modified, all of the logic stays the same a with the original proxy
    // the most important change is that the Instances data structure has a new member
    'tornado-proxy/ModifiedTornadoProxy.sol',
  ],
}
