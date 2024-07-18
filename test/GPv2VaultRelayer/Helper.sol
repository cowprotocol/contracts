// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {GPv2VaultRelayer, IVault} from "src/contracts/GPv2VaultRelayer.sol";

contract Helper is Test {
    address payable internal creator = payable(makeAddr("GPv2VaultRelayer.Helper creator"));
    IVault internal vault = IVault(makeAddr("GPv2VaultRelayer.Helper vault"));
    GPv2VaultRelayer internal vaultRelayer;

    function setUp() public {
        // Some calls check if the vault is a contract. `0xfe` is the designated
        // invalid instruction: this way, calling the vault without a mock
        // triggers a revert with `InvalidEFOpcode`.
        vm.etch(address(vault), hex"fe");

        vm.prank(creator);
        vaultRelayer = new GPv2VaultRelayer(vault);
    }
}
