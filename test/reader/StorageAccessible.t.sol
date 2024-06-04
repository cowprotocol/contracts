// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console} from "forge-std/Test.sol";
import {
    StorageAccessibleWrapper,
    ExternalStorageReader
} from "../../src/contracts/test/vendor/StorageAccessibleWrapper.sol";

contract StorageReadableTest is Test {
    StorageAccessibleWrapper wrapper;
    ExternalStorageReader reader;

    function setUp() public {
        wrapper = new StorageAccessibleWrapper();
        reader = new ExternalStorageReader();
    }
}
