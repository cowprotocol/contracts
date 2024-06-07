> [!IMPORTANT]  
> This repository is in the process of being migrated to the [Foundry](https://getfoundry.sh) Ethereum application development environment. Developers wishing to integrate and/or develop on the CoW Protocol smart contracts with hardhat should refer to tag [`v1.6.0`](https://github.com/cowprotocol/contracts/releases/tag/v1.6.0) [Browse files](https://github.com/cowprotocol/contracts/tree/1d673839a7402bdb2949175ebb61e8b5c4f39ecb).

# CoW Protocol

This repository contains the Solidity smart contract code for the **CoW Protocol** (formerly known as **Gnosis Protocol**).

Extensive [documentation](https://docs.cow.fi/cow-protocol/reference/contracts/core) is available detailing how the protocol works on a smart contract level.

## Getting Started

### Building the Project

```sh
yarn
yarn build
```

### Running Tests

```sh
yarn test
```

The tests can be run in "debug mode" as follows:

```sh
DEBUG=* yarn test
```

### Gas Reporter

Gas consumption can be reported by setting the `REPORT_GAS` flag when running tests as

```sh
REPORT_GAS=1 yarn test
```

### Benchmarking

This repository additionally includes tools for gas benchmarking and tracing.

In order to run a gas benchmark on a whole bunch of settlement scenarios:

```sh
yarn bench
```

These gas benchmarks can be compared against any other git reference and will default to the merge-base if omitted:

```sh
yarn bench:compare [<ref>]
```

In order to get a detailed trace of a settlement to identify how much gas is being spent where:

```sh
yarn bench:trace
```

## Deployment

### Deploying Contracts

Choose the network and gas price in wei for the deployment.
After replacing these values, run:

```sh
NETWORK='rinkeby'
GAS_PRICE_WEI='1000000000'
yarn deploy --network $NETWORK --gasprice $GAS_PRICE_WEI
```

New files containing details of this deployment will be created in the `deployment` folder.
These files should be committed to this repository.

### Verify Deployed Contracts

#### Etherscan

For verifying all deployed contracts:

```sh
export ETHERSCAN_API_KEY=<Your Key>
yarn verify:etherscan --network $NETWORK
```

Single contracts can be verified as well, but the constructor arguments must be explicitly given to the command.
A common example is the vault relayer contract, which is not automatically verified with the command above since it is only deployed indirectly during initialization. This contract can be manually verified with:

```sh
npx hardhat verify --network $NETWORK 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110  0xBA12222222228d8Ba445958a75a0704d566BF2C8
```

The first address is the vault relayer address, the second is the deployment input (usually, the Balancer vault).

#### Tenderly

For verifying all deployed contracts:

```sh
yarn verify:tenderly --network $NETWORK
```

For a single contract, named `GPv2Contract` and located at address `0xFeDbc87123caF3925145e1bD1Be844c03b36722f` in the example:

```sh
npx hardhat tenderly:verify --network $NETWORK GPv2Contract=0xFeDbc87123caF3925145e1bD1Be844c03b36722f
```

## Deployed Contract Addresses

This package additionally contains a `networks.json` file at the root with the address of each deployed contract as well the hash of the Ethereum transaction used to create the contract.

## Test coverage

Test coverage can be checked with the command

```sh
yarn coverage
```

A summary of coverage results are printed out to console. More detailed information is presented in the generated file `coverage/index.html`.

## Known issues

If a user creates an order with:
- zero sell amount
- zero buy amount
- partially fillable set to false

then this order could be executed an arbitrary amount of times instead of just a single time.
This means that any solver could drain the fee amount from the user until not enough funds are available anymore.

We recommend to never sign orders of this form and, if developing a contract that creates orders on behalf of other users, make sure at a contract level that such orders cannot be created.

## Transfer Ownership

There is a dedicated script to change the owner of the authenticator proxy.

The following parameters can be set:

```sh
export ETH_RPC_URL='https://rpc.url.example.com'
export NEW_OWNER=0x1111111111111111111111111111111111111111 
export RESET_MANAGER=true # true if the new owner should also become the manager, false otherwise
```

To test run the script from a specific owner (sender):

```sh
forge script scripts/TransferOwnership.s.sol:TransferOwnership --rpc-url "$ETH_RPC_URL" --sender 0xcA771eda0c70aA7d053aB1B25004559B918FE662
```

To actually execute the transaction:

```sh
forge script scripts/TransferOwnership.s.sol:TransferOwnership --rpc-url "$ETH_RPC_URL" --private-key 0x0000000000000000000000000000000000000000000000000000000000000001 --broadcast
```

## Releases

The content of this repo is published on NPM as [`@cowprotocol/contracts`](https://www.npmjs.com/package/@cowprotocol/contracts).

Maintainers this repository can manually trigger a new release. The steps are as follows:

1. Update the package version number in `./package.json` on branch `main`.

2. On GitHub, visit the "Actions" tab, "Publish package to NPM", "Run workflow" with `main` as the target branch.

Once the workflow has been executed successfully, a new NPM package version should be available as well as a new git tag named after the released version.
