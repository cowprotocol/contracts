// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Helper} from "./Helper.sol";

contract IsSolver is Helper {
    address solver = makeAddr("GPv2AllowListAuthentication.IsSolver: solver");

    function test_returns_true_when_given_address_is_a_recognized_solver() public {
        vm.prank(manager);
        authenticator.addSolver(solver);
        assertTrue(authenticator.isSolver(solver));
    }

    function test_returns_false_when_given_address_is_not_a_recognized_solver() public view {
        assertFalse(authenticator.isSolver(solver));
    }

    function test_returns_false_if_solver_was_added_and_then_removed() public {
        vm.prank(manager);
        authenticator.addSolver(solver);
        vm.prank(manager);
        authenticator.removeSolver(solver);
        assertFalse(authenticator.isSolver(solver));
    }
}
