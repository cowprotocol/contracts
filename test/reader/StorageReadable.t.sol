// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {StorageAccessibleWrapper} from "test/src/vendor/StorageAccessibleWrapper.sol";

contract StorageReadableTest is Test {
    StorageAccessibleWrapper instance;

    function setUp() public {
        instance = new StorageAccessibleWrapper();
    }

    function test_can_read_statically_sized_words() public {
        instance.setFoo(42);
        bytes memory actualBytes = instance.getStorageAt(instance.SLOT_FOO(), 1);
        bytes memory expectedBytes = abi.encode(42);
        assertEq(actualBytes, expectedBytes);
    }

    function test_can_read_fields_that_are_packed_into_single_storage_slot() public {
        instance.setBar(7);
        instance.setBam(13);
        bytes memory actualBytes = instance.getStorageAt(instance.SLOT_BAR(), 1);
        bytes memory expectedBytes = abi.encodePacked(new bytes(8), uint64(13), uint128(7));
        assertEq(actualBytes, expectedBytes);
    }

    function test_can_read_arrays_in_one_go() public {
        uint8 slot = instance.SLOT_BAZ();
        uint256[] memory arr = new uint256[](2);
        arr[0] = 42;
        arr[1] = 1337;
        instance.setBaz(arr);
        bytes memory data = instance.getStorageAt(slot, 1);
        uint256 length = abi.decode(data, (uint256));
        assertEq(length, 2);
        bytes memory packed = instance.getStorageAt(uint256(keccak256(abi.encode(slot))), length);
        (uint256 firstValue, uint256 secondValue) = abi.decode(packed, (uint256, uint256));
        assertEq(firstValue, 42);
        assertEq(secondValue, 1337);
    }

    function test_can_read_mappings() public {
        instance.setQuxKeyValue(42, 69);
        bytes memory data = instance.getStorageAt(uint256(keccak256(abi.encode([42, instance.SLOT_QUX()]))), 1);
        uint256 value = abi.decode(data, (uint256));
        assertEq(value, 69);
    }

    function test_can_read_structs() public {
        instance.setFoobar(19, 21);
        bytes memory packed = instance.getStorageAt(instance.SLOT_FOOBAR(), 10);
        (uint256 firstValue, uint256 secondValue) = abi.decode(packed, (uint256, uint256));
        assertEq(firstValue, 19);
        assertEq(secondValue, 21);
    }
}
