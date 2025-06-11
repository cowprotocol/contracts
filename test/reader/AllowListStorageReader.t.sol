// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2AllowListAuthentication, StorageAccessible} from "src/contracts/GPv2AllowListAuthentication.sol";
import {AllowListStorageReader} from "src/contracts/reader/AllowListStorageReader.sol";

contract AllowListStorageReaderTest is Test {
    address private manager = makeAddr("AllowListStorageReaderTest: manager");
    address private solver0 = makeAddr("AllowListStorageReaderTest: solver 0");
    address private solver1 = makeAddr("AllowListStorageReaderTest: solver 1");
    GPv2AllowListAuthentication private authenticator;
    AllowListStorageReader private reader;

    function setUp() public {
        authenticator = new GPv2AllowListAuthentication();
        authenticator.initializeManager(manager);

        reader = new AllowListStorageReader();
    }

    function readStorageAreSolver(
        StorageAccessible base,
        AllowListStorageReader storageReader,
        address[] memory prospectiveSolvers
    ) private returns (bool) {
        bytes memory result = base.simulateDelegatecall(
            address(storageReader), abi.encodeCall(AllowListStorageReader.areSolvers, (prospectiveSolvers))
        );
        return abi.decode(result, (bool));
    }

    function test_returns_true_when_all_specified_addresses_are_solvers() public {
        vm.startPrank(manager);
        authenticator.addSolver(solver0);
        authenticator.addSolver(solver1);
        vm.stopPrank();

        address[] memory solvers = new address[](2);
        solvers[0] = solver0;
        solvers[1] = solver1;
        assertTrue(readStorageAreSolver(authenticator, reader, solvers));
    }

    function test_returns_false_when_one_or_more_specified_addresses_are_not_solvers() public {
        vm.prank(manager);
        authenticator.addSolver(solver0);

        address[] memory solvers = new address[](2);
        solvers[0] = solver0;
        solvers[1] = solver1;
        assertFalse(readStorageAreSolver(authenticator, reader, solvers));
    }
}
