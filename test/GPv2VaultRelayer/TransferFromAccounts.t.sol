// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20, IVault, GPv2Transfer, GPv2Order} from "src/contracts/GPv2VaultRelayer.sol";

import {Helper} from "./Helper.sol";

contract TransferFromAccounts is Helper {
    function test_should_revert_if_not_called_by_the_creator() public {
        vm.prank(makeAddr("not the creator"));
        vm.expectRevert("GPv2: not creator");
        vaultRelayer.transferFromAccounts(new GPv2Transfer.Data[](0));
    }

    function test_should_execute_ERC20_and_Vault_transfers() public {
        IERC20 token0 = IERC20(makeAddr("token 0"));
        IERC20 token1 = IERC20(makeAddr("token 1"));
        IERC20 token2 = IERC20(makeAddr("token 2"));
        address trader0 = makeAddr("trader 0");
        address trader1 = makeAddr("trader 1");
        address trader2 = makeAddr("trader 2");

        uint256 amount = 13.37 ether;
        vm.mockCall(address(token0), abi.encodeCall(IERC20.transferFrom, (trader0, creator, amount)), abi.encode(true));

        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](2);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_EXTERNAL,
            asset: token1,
            amount: amount,
            sender: trader1,
            recipient: creator
        });
        vaultOps[1] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.WITHDRAW_INTERNAL,
            asset: token2,
            amount: amount,
            sender: trader2,
            recipient: creator
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](3);
        transfers[0] =
            GPv2Transfer.Data({account: trader0, token: token0, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        transfers[1] =
            GPv2Transfer.Data({account: trader1, token: token1, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        transfers[2] =
            GPv2Transfer.Data({account: trader2, token: token2, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});

        vm.prank(creator);
        vaultRelayer.transferFromAccounts(transfers);
    }

    function test_reverts_on_failed_ERC20_transfer() public {
        IERC20 token = IERC20(makeAddr("token"));
        address trader = makeAddr("trader");

        uint256 amount = 4.2 ether;
        vm.mockCallRevert(address(token), abi.encodeCall(IERC20.transferFrom, (trader, creator, amount)), "mock revert");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});

        vm.prank(creator);
        vm.expectRevert("mock revert");
        vaultRelayer.transferFromAccounts(transfers);
    }

    function test_reverts_on_failed_vault_transfer() public {
        IERC20 token = IERC20(makeAddr("token"));
        address trader = makeAddr("trader");

        uint256 amount = 4.2 ether;
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_EXTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: creator
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});

        vm.prank(creator);
        vm.expectRevert("mock revert");
        vaultRelayer.transferFromAccounts(transfers);
    }

    function test_reverts_on_failed_vault_withdrawal() public {
        IERC20 token = IERC20(makeAddr("token"));
        address trader = makeAddr("trader");

        uint256 amount = 4.2 ether;
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.WITHDRAW_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: creator
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});

        vm.prank(creator);
        vm.expectRevert("mock revert");
        vaultRelayer.transferFromAccounts(transfers);
    }
}
