// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IERC20, IVault} from "src/contracts/libraries/GPv2Transfer.sol";

import {GPv2TransferTestInterface} from "test/src/GPv2TransferTestInterface.sol";

// Todo once `test/GPv2Transfer.test.ts` is removed, the code in the file
// `test/src/GPv2TransferTestInterface.sol` should be copied here.
// solhint-disable-next-line no-empty-blocks
contract Harness is GPv2TransferTestInterface {}

contract Helper is Test {
    Harness internal executor;
    IERC20 internal token = IERC20(makeAddr("GPv2Transfer.Helper token"));
    IVault internal vault = IVault(makeAddr("GPv2Transfer.Helper vault"));

    function setUp() public {
        // Some calls check if the vault is a contract. `0xfe` is the designated
        // invalid instruction: this way, calling the vault without a mock
        // triggers a revert with `InvalidEFOpcode`.
        vm.etch(address(vault), hex"fe");
        vm.mockCallRevert(address(token), hex"", "unexpected call to mock token");
        vm.mockCallRevert(address(vault), hex"", "unexpected call to mock vault");

        executor = new Harness();
    }
}
