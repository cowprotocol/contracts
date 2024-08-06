// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2OrderTestInterface} from "test/src/GPv2OrderTestInterface.sol";

// TODO: move the content of `GPv2OrderTestInterface` here once all tests have been removed.
// solhint-disable-next-line no-empty-blocks
contract Harness is GPv2OrderTestInterface {}

contract Helper is Test {
    Harness internal executor;

    function setUp() public {
        executor = new Harness();
    }
}
