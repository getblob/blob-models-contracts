require("@nomiclabs/hardhat-waffle");
require("@nomicfoundation/hardhat-verify");

require('dotenv').config();

const privateKey = process.env.PRIVATE_KEY;

module.exports = {
    solidity: {
        compilers: [
            {
                version: `0.8.20`,
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 1
                    },
                    evmVersion: `london`,
                }
            }
        ],
    },
    etherscan: {
        apiKey: {
            'testnet': 'empty'
        },
        customChains: [
            {
                network: "testnet",
                chainId: 46630,
                urls: {
                    apiURL: "https://explorer.testnet.chain.robinhood.com/api",
                    browserURL: "https://explorer.testnet.chain.robinhood.com"
                }
            },
            {
                network: "mainnet",
                chainId: 4663,
                urls: {
                    apiURL: "https://robinhoodchain.blockscout.com/api",
                    browserURL: "https://robinhoodchain.blockscout.com"
                }
            }
        ]
    },
    networks: {
        testnet: {
            url: "https://rpc.testnet.chain.robinhood.com",
            accounts: [privateKey],
        },
        mainnet: {
            url: "https://rpc.mainnet.chain.robinhood.com",
            accounts: [privateKey],
        }
    },
    sourcify: {
        enabled: true
    },
    paths: {
        sources: "./src"
    },
};