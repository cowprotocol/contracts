// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {IVault, GPv2Authentication} from "src/contracts/GPv2Settlement.sol";
import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";
import {GPv2SettlementHarness} from "./GPv2SettlementHarness.sol";

abstract contract GPv2SettlementHelper is Test {
    using stdJson for string;

    GPv2Authentication internal authenticator;
    IVault internal vault;

    GPv2SettlementHarness internal settlement;

    function setUp() public {
        // Configure addresses
        address deployer = makeAddr("deployer");
        address owner = makeAddr("owner");
        vm.startPrank(deployer);

        // Deploy the allowlist manager
        GPv2AllowListAuthentication allowList = new GPv2AllowListAuthentication();
        allowList.initializeManager(owner);
        authenticator = allowList;

        // Deploy the vault contract
        vault = deployBalancerVault();

        // Deploy the settlement contract
        settlement = new GPv2SettlementHarness(authenticator, vault);

        // Reset the prank
        vm.stopPrank();
    }

    function deployBalancerVault() private returns (IVault vault_) {
        string memory path = string.concat(vm.projectRoot(), "/", "balancer/Vault.json");
        string memory json = vm.readFile(path);
        bytes memory bytecode = json.parseRaw(".bytecode");

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            vault_ := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}
