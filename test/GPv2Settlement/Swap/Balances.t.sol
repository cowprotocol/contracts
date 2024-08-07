// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, GPv2Signing, IERC20, IVault} from "src/contracts/GPv2Settlement.sol";

import {Helper} from "../Helper.sol";
import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";

contract Balances is Helper {
    using SwapEncoder for SwapEncoder.State;

    function test_performs_a_swap_to_sell_erc20_from_buy_erc20_when_specified() public {
        performs_a_swap_with_the_specified_balances(GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_ERC20);
    }

    function test_performs_a_swap_to_sell_erc20_from_buy_internal_when_specified() public {
        performs_a_swap_with_the_specified_balances(GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_INTERNAL);
    }

    function test_performs_a_swap_to_sell_external_from_buy_erc20_when_specified() public {
        performs_a_swap_with_the_specified_balances(GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_ERC20);
    }

    function test_performs_a_swap_to_sell_external_from_buy_internal_when_specified() public {
        performs_a_swap_with_the_specified_balances(GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_INTERNAL);
    }

    function test_performs_a_swap_to_sell_internal_from_buy_erc20_when_specified() public {
        performs_a_swap_with_the_specified_balances(GPv2Order.BALANCE_INTERNAL, GPv2Order.BALANCE_ERC20);
    }

    function test_performs_a_swap_to_sell_internal_from_buy_internal_when_specified() public {
        performs_a_swap_with_the_specified_balances(GPv2Order.BALANCE_INTERNAL, GPv2Order.BALANCE_INTERNAL);
    }

    function performs_a_swap_with_the_specified_balances(bytes32 sellTokenBalance, bytes32 buyTokenBalance) private {
        address payable receiver = payable(makeAddr("receiver"));
        IERC20 sellToken = IERC20(makeAddr("sell token"));
        IERC20 buyToken = IERC20(makeAddr("buy token"));

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: receiver,
            sellAmount: 0,
            buyAmount: 0,
            validTo: 0,
            appData: bytes32(0),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_SELL,
            sellTokenBalance: sellTokenBalance,
            buyTokenBalance: buyTokenBalance,
            partiallyFillable: false
        });

        SwapEncoder.State storage swapEncoder = SwapEncoder.makeSwapEncoder();
        swapEncoder.signEncodeTrade({
            vm: vm,
            owner: trader,
            order: order,
            domainSeparator: domainSeparator,
            signingScheme: GPv2Signing.Scheme.Eip712,
            executedAmount: 0
        });

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: trader.addr,
            fromInternalBalance: sellTokenBalance == GPv2Order.BALANCE_INTERNAL,
            recipient: receiver,
            toInternalBalance: buyTokenBalance == GPv2Order.BALANCE_INTERNAL
        });
        vm.mockCall(
            address(vault),
            abi.encodeCall(
                IVault.batchSwap,
                (IVault.SwapKind.GIVEN_IN, encodedSwap.swaps, encodedSwap.tokens, funds, new int256[](2), 0)
            ),
            abi.encode(new int256[](2))
        );

        if (sellTokenBalance == GPv2Order.BALANCE_ERC20) {
            vm.mockCall(
                address(sellToken),
                abi.encodeCall(IERC20.transferFrom, (trader.addr, address(settlement), order.feeAmount)),
                abi.encode(true)
            );
        } else {
            IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
            vaultOps[0] = IVault.UserBalanceOp({
                // `kind` is just some placeholder value
                kind: IVault.UserBalanceOpKind.TRANSFER_INTERNAL,
                asset: order.sellToken,
                amount: order.feeAmount,
                sender: trader.addr,
                recipient: payable(address(settlement))
            });

            if (sellTokenBalance == GPv2Order.BALANCE_EXTERNAL) {
                vaultOps[0].kind = IVault.UserBalanceOpKind.TRANSFER_EXTERNAL;
            } else {
                assert(sellTokenBalance == GPv2Order.BALANCE_INTERNAL);
                vaultOps[0].kind = IVault.UserBalanceOpKind.TRANSFER_INTERNAL;
            }

            vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");
        }

        vm.prank(solver);
        swap(swapEncoder.encode());
    }
}
