// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

import {Helper} from "./Helper.sol";

contract AddSolver is Helper {
    address solver = makeAddr("GPv2AllowListAuthentication.AddSolver: solver");

    function test_should_allow_manager_to_add_a_solver() public {
        vm.prank(manager);
        authenticator.addSolver(solver);
    }

    function test_reverts_when_owner_adds_a_solver() public {
        vm.prank(owner);
        vm.expectRevert("GPv2: caller not manager");
        authenticator.addSolver(solver);
    }

    function test_reverts_when_unauthorized_address_adds_a_solver() public {
        vm.prank(makeAddr("any address"));
        vm.expectRevert("GPv2: caller not manager");
        authenticator.addSolver(solver);
    }

    function test_should_emit_a_SolverAdded_event() public {
        vm.prank(manager);
        vm.expectEmit();
        emit GPv2AllowListAuthentication.SolverAdded(solver);
        authenticator.addSolver(solver);
    }
}
