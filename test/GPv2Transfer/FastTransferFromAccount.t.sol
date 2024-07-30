// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, GPv2Transfer, IERC20, IVault} from "src/contracts/libraries/GPv2Transfer.sol";

import {Helper} from "./Helper.sol";

contract FastTransferFromAccount is Helper {
    address private trader = makeAddr("GPv2Transfer.fastTransferFromAccounts trader");
    address payable private recipient = payable(makeAddr("GPv2Transfer.fastTransferFromAccounts recipient"));
    uint256 private amount = 0.1337 ether;

    function test_should_transfer_ERC20_amount_to_recipient() public {
        vm.mockCall(address(token), abi.encodeCall(IERC20.transferFrom, (trader, recipient, amount)), abi.encode(true));
        GPv2Transfer.Data memory transfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
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

        GPv2Transfer.Data memory transfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
    }

    function test_should_transfer_internal_amount_to_recipient() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: recipient
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");

        GPv2Transfer.Data memory transfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
    }

    function reverts_when_mistakenly_trying_to_transfer_Ether(bytes32 balanceLocation) private {
        GPv2Transfer.Data memory transfer = GPv2Transfer.Data({
            account: trader,
            token: IERC20(GPv2Transfer.BUY_ETH_ADDRESS),
            amount: amount,
            balance: balanceLocation
        });
        vm.expectRevert("GPv2: cannot transfer native ETH");
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
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
        GPv2Transfer.Data memory transfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_ERC20});
        vm.expectRevert("mock revert");
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
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

        GPv2Transfer.Data memory transfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_EXTERNAL});
        vm.expectRevert("mock revert");
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
    }

    function test_reverts_on_failed_Vault_internal_transfer() public {
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_INTERNAL,
            asset: token,
            amount: amount,
            sender: trader,
            recipient: recipient
        });
        vm.mockCallRevert(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), "mock revert");

        GPv2Transfer.Data memory transfer =
            GPv2Transfer.Data({account: trader, token: token, amount: amount, balance: GPv2Order.BALANCE_INTERNAL});
        vm.expectRevert("mock revert");
        executor.fastTransferFromAccountTest(vault, transfer, recipient);
    }
}
