import "@nomiclabs/hardhat-waffle";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@tenderly/hardhat-tenderly";
import "@nomicfoundation/hardhat-verify";

import dotenv from "dotenv";
import type { HttpNetworkUserConfig } from "hardhat/types";
import type { MochaOptions } from "mocha";
import yargs from "yargs";

import { setupTasks } from "./src/tasks";

const argv = yargs
  .option("network", {
    type: "string",
    default: "hardhat",
  })
  .help(false)
  .version(false)
  .parseSync();

// Load environment variables.
dotenv.config();
const {
  INFURA_KEY,
  MNEMONIC,
  PK,
  REPORT_GAS,
  MOCHA_CONF,
  NODE_URL,
  ETHERSCAN_API_KEY,
} = process.env;

const DEFAULT_MNEMONIC =
  "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat";

const sharedNetworkConfig: HttpNetworkUserConfig = {};
if (PK) {
  sharedNetworkConfig.accounts = [PK];
} else {
  sharedNetworkConfig.accounts = {
    mnemonic: MNEMONIC || DEFAULT_MNEMONIC,
  };
}

if (
  ["rinkeby", "goerli", "mainnet"].includes(argv.network) &&
  NODE_URL === undefined &&
  INFURA_KEY === undefined
) {
  throw new Error(
    `Could not find Infura key in env, unable to connect to network ${argv.network}`,
  );
}

if (NODE_URL !== undefined) {
  sharedNetworkConfig.url = NODE_URL;
}

const mocha: MochaOptions = {};
let initialBaseFeePerGas: number | undefined = undefined;
switch (MOCHA_CONF) {
  case undefined:
    break;
  case "coverage":
    // End to end and task tests are skipped because:
    // - coverage tool does not play well with proxy deployment with
    //   hardhat-deploy
    // - coverage compiles without optimizer and, unlike Waffle, hardhat-deploy
    //   strictly enforces the contract size limits from EIP-170
    mocha.grep = /^(?!E2E|Task)/;
    // Note: unit is Wei, not GWei. This is a workaround to make the coverage
    // tool work with the London hardfork.
    initialBaseFeePerGas = 1;
    break;
  case "ignored in coverage":
    mocha.grep = /^E2E|Task/;
    break;
  default:
    throw new Error("Invalid MOCHA_CONF");
}

setupTasks();

export default {
  mocha,
  paths: {
    artifacts: "build/artifacts",
    cache: "build/cache",
    deploy: "src/deploy",
    sources: "src/contracts",
  },
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
      {
        // Compiler for the Gas Token v1
        version: "0.4.11",
      },
    ],
  },
  networks: {
    hardhat: {
      blockGasLimit: 12.5e6,
      initialBaseFeePerGas,
    },
    mainnet: {
      url: `https://mainnet.infura.io/v3/${INFURA_KEY}`,
      ...sharedNetworkConfig,
      chainId: 1,
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${INFURA_KEY}`,
      ...sharedNetworkConfig,
      chainId: 4,
    },
    goerli: {
      url: `https://goerli.infura.io/v3/${INFURA_KEY}`,
      ...sharedNetworkConfig,
      chainId: 5,
    },
    sepolia: {
      url: "https://ethereum-sepolia.publicnode.com",
      ...sharedNetworkConfig,
      chainId: 11155111,
    },
    xdai: {
      url: "https://rpc.gnosischain.com",
      ...sharedNetworkConfig,
      chainId: 100,
    },
    arbitrumOne: {
      ...sharedNetworkConfig,
      url: "https://arb1.arbitrum.io/rpc",
    },
    base: {
      ...sharedNetworkConfig,
      url: "https://mainnet.base.org",
      chainId: 8453,
    },
    bsc: {
      ...sharedNetworkConfig,
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
    },
    polygon: {
      ...sharedNetworkConfig,
      url: "https://polygon-rpc.com/",
      chainId: 137,
    },
    optimism: {
      ...sharedNetworkConfig,
      url: "https://mainnet.optimism.io/",
      chainId: 10,
    },
    avalanche: {
      ...sharedNetworkConfig,
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
    },
  },
  namedAccounts: {
    // Note: accounts defined by a number refer to the the accounts as configured
    // by the current network.
    deployer: 0,
    owner: {
      // The contract deployment addresses depend on the owner address.
      // To have the same addresses on all networks, the owner must be the same.
      default: "0x6Fb5916c0f57f88004d5b5EB25f6f4D77353a1eD",
      hardhat: 1,
      localhost: 1,
    },
    manager: {
      default: "0x6Fb5916c0f57f88004d5b5EB25f6f4D77353a1eD",
      hardhat: 2,
      localhost: 2,
    },
  },
  gasReporter: {
    enabled: REPORT_GAS ? true : false,
    currency: "USD",
    gasPrice: 21,
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API_KEY,
      arbitrumOne: ETHERSCAN_API_KEY,
      base: ETHERSCAN_API_KEY,
      optimisticEthereum: ETHERSCAN_API_KEY,
      polygon: ETHERSCAN_API_KEY,
      avalanche: ETHERSCAN_API_KEY,
    },
    customChains: [
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org",
        },
      },
      {
        network: "avalanche",
        chainId: 43114,
        urls: {
          apiURL: "https://api.snowscan.xyz/api",
          browserURL: "https://snowscan.xyz",
        },
      },
    ],
  },
};
