// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, GPv2Transfer, IERC20, IVault} from "src/contracts/libraries/GPv2Transfer.sol";

import {Helper} from "./Helper.sol";

contract TransferFromAccounts is Helper {
    address private trader = makeAddr("GPv2Transfer.transferFromAccounts trader");
    address payable private recipient = payable(makeAddr("GPv2Transfer.transferFromAccounts recipient"));
    uint256 private amount = 0.1337 ether;

    function test_should_transfer_ERC20_amount_to_recipient() public {
        vm.mockCall(address(token), abi.encodeCall(IERC20.transferFrom, (trader, recipient, amount)), abi.encode(true));
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function test_should_transfer_external_amount_to_recipient() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_EXTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: recipient
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function test_should_transfer_internal_amount_to_recipient() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.WITHDRAW_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: recipient
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function test_should_transfer_many_external_and_internal_amounts_to_recipient() public {
        uint256 numTraders = 42;
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](numTraders);
        IVault.UserBalanceOp[] memory expectedVaultOps = new IVault.UserBalanceOp[](numTraders / 3 * 2 + numTraders % 3);
        uint256 erc20OpCount = 0;
        for (uint256 i = 0; i < numTraders; i++) {
            bool isErc20 = i % 3 == 0;
            bool isExternal = i % 3 == 1;
            address traderi = makeAddr(string.concat("trader ", vm.toString(i)));
            transfers[i] = GPv2Transfer.Data({
                account: traderi,
                token: token,
                amount: amount,
                balance: isErc20
                    ? GPv2Order.BALANCE_ERC20
                    : (isExternal ? GPv2Order.BALANCE_EXTERNAL : GPv2Order.BALANCE_INTERNAL)
            });
            if (isErc20) {
                erc20OpCount += 1;
                vm.mockCall(
                    address(token), abi.encodeCall(IERC20.transferFrom, (traderi, recipient, amount)), abi.encode(true)
                );
            } else {
                expectedVaultOps[i / 3 * 2 + (isExternal ? 0 : 1)] = IVault.UserBalanceOp({
                    kind: isExternal
                        ? IVault.UserBalanceOpKind.TRANSFER_EXTERNAL
                        : IVault.UserBalanceOpKind.WITHDRAW_INTERNAL,
                    asset: token,
                    amount: amount,
                    sender: traderi,
                    recipient: recipient
                });
            }
        }

        // NOTE: Make sure we have at least 2 of each flavour of transfer, this
        // avoids this test not achieving what it expects because of reasonable
        // changes elsewhere in the file (like only having 3 traders for
        // example).
        assertGt(erc20OpCount, 1);
        assertGt(expectedVaultOps.length, 1);

        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (expectedVaultOps)), hex"");
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function reverts_when_mistakenly_trying_to_transfer_Ether(bytes32 balanceLocation) private {
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] = GPv2Transfer.Data({
            account: trader,
            token: IERC20(GPv2Transfer.BUY_ETH_ADDRESS),
            amount: amount,
            balance: balanceLocation
        });
        vm.expectRevert("GPv2: cannot transfer native ETH");
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function test_reverts_when_mistakenly_trying_to_transfer_Ether_erc20() public {
        reverts_when_mistakenly_trying_to_transfer_Ether(GPv2Order.BALANCE_ERC20);
    }

    function test_reverts_when_mistakenly_trying_to_transfer_Ether_internal() public {
        reverts_when_mistakenly_trying_to_transfer_Ether(GPv2Order.BALANCE_INTERNAL);
    }

    function test_reverts_when_mistakenly_trying_to_transfer_Ether_external() public {
        reverts_when_mistakenly_trying_to_transfer_Ether(GPv2Order.BALANCE_EXTERNAL);
    }

    function test_reverts_on_failed_ERC20_transfer() public {
        vm.mockCallRevert(
            address(token), abi.encodeCall(IERC20.transferFrom, (trader, recipient, amount)), "mock revert"
        );
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        vm.expectRevert("mock revert");
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function test_reverts_on_failed_Vault_external_transfer() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_EXTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: recipient
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        vm.expectRevert("mock revert");
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }

    function test_reverts_on_failed_Vault_internal_transfer() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.WITHDRAW_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: recipient
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        vm.expectRevert("mock revert");
        executor.transferFromAccountsTest(vault, transfers, recipient);
    }
}
