// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";
import {GPv2EIP1967} from "src/contracts/libraries/GPv2EIP1967.sol";

contract GPv2AllowListAuthenticationHarness is GPv2AllowListAuthentication {
    constructor(address owner) {
        GPv2EIP1967.setAdmin(owner);
    }
}

contract Helper is Test {
    GPv2AllowListAuthenticationHarness authenticator;
    address owner = makeAddr("GPv2AllowListAuthentication.Helper: default owner");
    address manager = makeAddr("GPv2AllowListAuthentication.Helper: default manager");
    address deployer = makeAddr("GPv2AllowListAuthentication.Helper: default deployer");

    function setUp() public {
        // NOTE: This deploys the test interface contract which emulates being
        // proxied by an EIP-1967 compatible proxy for unit testing purposes.
        vm.prank(deployer);
        authenticator = new GPv2AllowListAuthenticationHarness(owner);
        authenticator.initializeManager(manager);
    }
}
