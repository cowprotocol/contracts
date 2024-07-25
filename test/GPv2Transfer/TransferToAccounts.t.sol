// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, GPv2Transfer, IERC20, IVault} from "src/contracts/libraries/GPv2Transfer.sol";

import {Helper} from "./Helper.sol";

contract TransferToAccounts is Helper {
    address payable private trader = payable(makeAddr("GPv2Transfer.transferToAccounts trader"));
    uint256 private amount = 0.1337 ether;

    struct TraderWithBalance {
        address trader;
        uint256 balance;
    }

    function test_should_transfer_external_amount_to_recipient() public {
        vm.mockCall(address(token), abi.encodeCall(IERC20.transfer, (trader, amount)), abi.encode(true));
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        executor.transferToAccountsTest(vault, transfers);
    }

    function test_should_transfer_internal_amount_to_recipient() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token,
            amount: amount,
            sender: address(executor),
            recipient: trader
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        executor.transferToAccountsTest(vault, transfers);
    }

    function test_should_transfer_Ether_amount_to_account() public {
        vm.deal(address(executor), amount);
        uint256 initialBalance = trader.balance;
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] = GPv2Transfer.Data({
            account: trader,
            token: IERC20(GPv2Transfer.BUY_ETH_ADDRESS),
            amount: amount,
            balance: GPv2Order.BALANCE_ERC20
        });
        executor.transferToAccountsTest(vault, transfers);
        assertEq(trader.balance, initialBalance + amount);
    }

    function test_should_transfer_many_external_and_internal_amounts_to_recipient() public {
        uint256 numTraders = 42;
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](numTraders);
        IVault.UserBalanceOp[] memory expectedVaultOps =
            new IVault.UserBalanceOp[](numTraders / 3 + ((numTraders % 3 == 1) ? 1 : 0));
        TraderWithBalance[] memory ethTraderStartingBalance = new TraderWithBalance[](numTraders / 3);
        uint256 erc20OpCount = 0;
        for (uint256 i = 0; i < numTraders; i++) {
            bool isExternal = i % 3 == 0;
            bool isInternal = i % 3 == 1;
            bool isEth = i % 3 == 2;
            address payable traderi = payable(makeAddr(string.concat("trader ", vm.toString(i))));
            transfers[i] = GPv2Transfer.Data({
                account: traderi,
                token: isEth ? IERC20(GPv2Transfer.BUY_ETH_ADDRESS) : token,
                amount: amount,
                balance: isInternal ? GPv2Order.BALANCE_INTERNAL : GPv2Order.BALANCE_ERC20
            });
            if (isExternal) {
                erc20OpCount += 1;
                vm.mockCall(address(token), abi.encodeCall(IERC20.transfer, (traderi, amount)), abi.encode(true));
            } else if (isInternal) {
                expectedVaultOps[i / 3] = IVault.UserBalanceOp({
                    kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
                    asset: token,
                    amount: amount,
                    sender: address(executor),
                    recipient: traderi
                });
            } else {
                ethTraderStartingBalance[i / 3] = TraderWithBalance({trader: traderi, balance: traderi.balance});
            }
        }

        assertGt(erc20OpCount, 1);
        assertGt(expectedVaultOps.length, 1);
        assertGt(ethTraderStartingBalance.length, 1);

        vm.deal(address(executor), numTraders * amount);
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (expectedVaultOps)), hex"");
        executor.transferToAccountsTest(vault, transfers);

        for (uint256 i = 0; i < ethTraderStartingBalance.length; i++) {
            assertEq(ethTraderStartingBalance[i].trader.balance, ethTraderStartingBalance[i].balance + amount);
        }
    }

    function test_reverts_on_failed_ERC20_transfer() public {
        vm.mockCallRevert(address(token), abi.encodeCall(IERC20.transfer, (trader, amount)), "mock revert");
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        vm.expectRevert("mock revert");
        executor.transferToAccountsTest(vault, transfers);
    }

    function test_reverts_on_failed_Vault_deposit() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token,
            amount: amount,
            sender: address(executor),
            recipient: trader
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        vm.expectRevert("mock revert");
        executor.transferToAccountsTest(vault, transfers);
    }

    function test_should_revert_when_transfering_Ether_with_internal_balance() public {
        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] = GPv2Transfer.Data({
            account: trader,
            token: IERC20(GPv2Transfer.BUY_ETH_ADDRESS),
            amount: amount,
            balance: GPv2Order.BALANCE_INTERNAL
        });
        vm.expectRevert("GPv2: unsupported internal ETH");
        executor.transferToAccountsTest(vault, transfers);
    }
}
