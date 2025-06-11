// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2Transfer, IERC20, IVault} from "src/contracts/libraries/GPv2Transfer.sol";

contract Harness {
    function fastTransferFromAccountTest(IVault vault, GPv2Transfer.Data calldata transfer, address recipient)
        external
    {
        GPv2Transfer.fastTransferFromAccount(vault, transfer, recipient);
    }

    function transferFromAccountsTest(IVault vault, GPv2Transfer.Data[] calldata transfers, address recipient)
        external
    {
        GPv2Transfer.transferFromAccounts(vault, transfers, recipient);
    }

    function transferToAccountsTest(IVault vault, GPv2Transfer.Data[] memory transfers) external {
        GPv2Transfer.transferToAccounts(vault, transfers);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}

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
