// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2SigningTestInterface} from "test/src/GPv2SigningTestInterface.sol";

// TODO: move the content of `GPv2SigningTestInterface` here once all tests have
// been removed.
// solhint-disable-next-line no-empty-blocks
contract Harness is GPv2SigningTestInterface {}

contract Helper is Test {
    Harness internal executor;
    bytes32 internal domainSeparator;

    function setUp() public {
        executor = new Harness();
        domainSeparator = executor.domainSeparator();
    }
}
