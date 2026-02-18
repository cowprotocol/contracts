// This file exists to import the types for use in the rest of the codebase, since `hardhat.config.ts` is deliberately excluded
// from `tsc` due to build issues.
// Including `hardhat-cannon` causes a chain of dependencies to be included that breaks the typescript build 
// in certain typescript environments, so we don't include it in this file.

import "@nomiclabs/hardhat-waffle";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@tenderly/hardhat-tenderly";
import "@nomicfoundation/hardhat-verify";
