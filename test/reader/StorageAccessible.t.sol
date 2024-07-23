// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {ExternalStorageReader, StorageAccessibleWrapper} from "./StorageAccessibleWrapper.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {ViewStorageAccessible} from "src/contracts/mixins/StorageAccessible.sol";

contract StorageAccessibleTest is Test {
    StorageAccessibleWrapper instance;
    ExternalStorageReader reader;

    function setUp() public {
        instance = new StorageAccessibleWrapper();
        reader = new ExternalStorageReader();
    }

    function test_can_invoke_function_in_the_context_of_previously_deployed_contract() public {
        instance.setFoo(42);
        bytes memory data = instance.simulateDelegatecall(address(reader), abi.encodeWithSignature("getFoo()"));
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 42);
    }

    function test_can_simulateDelegatecall_a_function_with_side_effects() public {
        instance.setFoo(42);
        vm.startStateDiffRecording();

        bytes memory data =
            instance.simulateDelegatecall(address(reader), abi.encodeWithSignature("setAndGetFoo(uint256)", 69));
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 69);

        // Make sure foo is not actually changed
        uint256 foo = reader.invokeStaticDelegatecall(
            ViewStorageAccessible(address(instance)), abi.encodeWithSignature("getFoo()")
        );
        assertEq(foo, 42);

        // Using state changes to make sure foo isn't changed
        Vm.AccountAccess[] memory records = vm.stopAndReturnStateDiff();
        for (uint256 i; i < records.length; i++) {
            uint256 storageCalls = records[i].storageAccesses.length;
            for (uint256 j; j < storageCalls; j++) {
                if (records[i].storageAccesses[j].isWrite) {
                    assertEq(records[i].storageAccesses[j].reverted, true);
                }
            }
        }
    }

    function test_can_simulateDelegatecall_a_function_that_reverts() public {
        vm.expectRevert();
        instance.simulateDelegatecall(address(reader), abi.encodeWithSignature("doRevert()"));
    }

    function test_allows_detection_of_reverts_when_invoked_from_other_smart_contract() public {
        vm.expectRevert();
        reader.invokeDoRevertViaStorageAccessible(instance);
    }
}
