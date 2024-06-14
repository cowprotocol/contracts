// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

import {Helper} from "./Helper.sol";

contract RemoveSolver is Helper {
    address solver = makeAddr("GPv2AllowListAuthentication.RemoveSolver: solver");

    function test_should_allow_manager_to_remove_a_solver() public {
        vm.prank(manager);
        authenticator.removeSolver(solver);
    }

    function test_reverts_when_owner_removes_a_solver() public {
        vm.prank(owner);
        vm.expectRevert("GPv2: caller not manager");
        authenticator.removeSolver(solver);
    }

    function test_reverts_when_unauthorized_address_adds_a_solver() public {
        vm.prank(makeAddr("any address"));
        vm.expectRevert("GPv2: caller not manager");
        authenticator.removeSolver(solver);
    }

    function test_should_emit_a_SolverRemoved_event() public {
        vm.prank(manager);
        vm.expectEmit();
        emit GPv2AllowListAuthentication.SolverRemoved(solver);
        authenticator.removeSolver(solver);
    }
}
