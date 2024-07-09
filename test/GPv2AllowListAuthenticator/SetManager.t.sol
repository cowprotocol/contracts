// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

import {Helper} from "./Helper.sol";

contract SetManager is Helper {
    address newManager = makeAddr("GPv2AllowListAuthentication.SetManager: new manager");

    function test_should_be_settable_by_current_owner() public {
        vm.prank(owner);
        authenticator.setManager(newManager);
        assertEq(authenticator.manager(), newManager);
    }

    function test_should_be_settable_by_current_manager() public {
        vm.prank(manager);
        authenticator.setManager(newManager);
        assertEq(authenticator.manager(), newManager);
    }

    function test_should_revert_when_being_set_by_unauthorized_address() public {
        vm.prank(makeAddr("unauthorized address"));
        vm.expectRevert("GPv2: not authorized");
        authenticator.setManager(newManager);
    }

    function test_should_emit_a_ManagerChanged_event() public {
        vm.prank(manager);
        vm.expectEmit();
        emit GPv2AllowListAuthentication.ManagerChanged(newManager, manager);
        authenticator.setManager(newManager);
    }
}
