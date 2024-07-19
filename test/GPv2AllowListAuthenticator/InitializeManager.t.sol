// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

import {Helper, GPv2AllowListAuthenticationHarness} from "./Helper.sol";

contract InitializeManager is Helper {
    function test_should_initialize_the_manager() public view {
        assertEq(authenticator.manager(), manager);
    }

    function test_deployer_is_not_the_manager() public view {
        assertNotEq(authenticator.manager(), deployer);
    }

    function test_owner_is_not_the_manager() public view {
        assertNotEq(authenticator.manager(), owner);
    }

    function test_reverts_when_initializing_twice() public {
        vm.expectRevert("Initializable: initialized");
        authenticator.initializeManager(makeAddr("any address"));

        // Also reverts when called by owner.
        vm.expectRevert("Initializable: initialized");
        vm.prank(owner);
        authenticator.initializeManager(makeAddr("any address"));
    }

    function test_should_emit_a_ManagerChangedd_event() public {
        authenticator = new GPv2AllowListAuthenticationHarness(owner);
        vm.expectEmit();
        emit GPv2AllowListAuthentication.ManagerChanged(manager, address(0));
        authenticator.initializeManager(manager);
    }
}
