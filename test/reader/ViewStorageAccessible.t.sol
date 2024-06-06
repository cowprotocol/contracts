// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {StorageAccessibleWrapper, ExternalStorageReader} from "src/contracts/test/vendor/StorageAccessibleWrapper.sol";
import {ViewStorageAccessible} from "src/contracts/mixins/StorageAccessible.sol";

contract StorageAccessibleTest is Test {
    StorageAccessibleWrapper instance;
    ExternalStorageReader reader;

    function setUp() public {
        instance = new StorageAccessibleWrapper();
        reader = new ExternalStorageReader();
    }

    function test_simulate() public {
        instance.setFoo(42);
        uint256 result = reader.invokeStaticDelegatecall(
            ViewStorageAccessible(address(instance)), abi.encodeWithSignature("getFoo()")
        );
        assertEq(result, 42);
    }

    function test_cannot_simulate_state_changes() public {
        instance.setFoo(42);
        vm.expectRevert();
        reader.invokeStaticDelegatecall(
            ViewStorageAccessible(address(instance)), abi.encodeWithSignature("setAndGetFoo(uint256)", 69)
        );
    }
}
