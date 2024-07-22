// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {
    GPv2VaultRelayer, GPv2Transfer, IERC20, IVault, GPv2Transfer, GPv2Order
} from "src/contracts/GPv2VaultRelayer.sol";

import {BatchSwapWithFeeHelper} from "./Helper.sol";

contract BatchSwapWithFeeFeeTransfer is BatchSwapWithFeeHelper {
    function test_should_perform_ERC20_transfer_when_not_using_direct_ERC20_balance() public {
        address trader = makeAddr("trader");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 4.2 ether;

        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](0)));
        vm.mockCall(address(token), abi.encodeCall(IERC20.transferFrom, (trader, creator, amount)), abi.encode(true));

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        batchSwapWithFee(vaultRelayer, swapWithFees);
    }

    function test_should_perform_Vault_external_balance_transfer_when_specified() public {
        address trader = makeAddr("trader");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 4.2 ether;

        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_EXTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: creator
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](0)));

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        batchSwapWithFee(vaultRelayer, swapWithFees);
    }

    function test_should_perform_Vault_internal_balance_transfer_when_specified() public {
        address trader = makeAddr("trader");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 4.2 ether;

        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: creator
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](0)));

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        batchSwapWithFee(vaultRelayer, swapWithFees);
    }

    function test_reverts_on_failed_ERC20_transfer() public {
        address trader = makeAddr("trader");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 4.2 ether;

        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](0)));
        vm.mockCallRevert(address(token), abi.encodeCall(IERC20.transferFrom, (trader, creator, amount)), "mock revert");

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        vm.expectRevert("mock revert");
        batchSwapWithFee(vaultRelayer, swapWithFees);
    }

    function test_reverts_on_failed_Vault_external_transfer() public {
        address trader = makeAddr("trader");
        IERC20 token = IERC20(makeAddr("token"));
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
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](0)));

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        vm.expectRevert("mock revert");
        batchSwapWithFee(vaultRelayer, swapWithFees);
    }

    function test_revert_on_failed_Vault_internal_transfer() public {
        address trader = makeAddr("trader");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 4.2 ether;

        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: creator
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](0)));

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        vm.expectRevert("mock revert");
        batchSwapWithFee(vaultRelayer, swapWithFees);
    }
}
