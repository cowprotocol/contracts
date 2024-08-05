// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, GPv2Settlement, GPv2Signing, IERC20, IVault} from "src/contracts/GPv2Settlement.sol";

import {Helper} from "../Helper.sol";

import {Order} from "test/libraries/Order.sol";
import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";

abstract contract Variant is Helper {
    using SwapEncoder for SwapEncoder.State;

    IERC20 private sellToken = IERC20(makeAddr("GPv2Settlement.Swap.Variants sell token"));
    IERC20 private buyToken = IERC20(makeAddr("GPv2Settlement.Swap.Variants buy token"));

    uint256 constant sellAmount = 4.2 ether;
    uint256 constant buyAmount = 13.37 ether;

    bytes32 immutable kind;

    constructor(bytes32 _kind) {
        kind = _kind;
    }

    function defaultOrder() private view returns (GPv2Order.Data memory) {
        return GPv2Order.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            receiver: address(0),
            validTo: 0x01020304,
            appData: keccak256("GPv2Settlement.Swap.Variants default app data"),
            feeAmount: 1 ether,
            sellTokenBalance: GPv2Order.BALANCE_INTERNAL,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            partiallyFillable: true,
            kind: kind
        });
    }

    function defaultOrderUid() private view returns (bytes memory) {
        return Order.computeOrderUid(defaultOrder(), domainSeparator, trader.addr);
    }

    function encodedDefaultSwap() private returns (SwapEncoder.EncodedSwap memory) {
        return encodedDefaultSwap(0);
    }

    function encodedDefaultSwap(uint256 executedAmount) private returns (SwapEncoder.EncodedSwap memory) {
        GPv2Order.Data memory order = defaultOrder();

        SwapEncoder.State storage swapEncoder = SwapEncoder.makeSwapEncoder();

        swapEncoder.signEncodeTrade({
            vm: vm,
            owner: trader,
            order: order,
            domainSeparator: domainSeparator,
            signingScheme: GPv2Signing.Scheme.Eip712,
            executedAmount: executedAmount
        });
        return swapEncoder.encode();
    }

    function mockBalancerVaultCallsReturn(int256 mockSellAmount, int256 mockBuyAmount) private {
        int256[] memory output = new int256[](2);
        output[0] = mockSellAmount;
        output[1] = mockBuyAmount;
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(output));
        vm.mockCall(address(vault), abi.encodePacked(IVault.manageUserBalance.selector), hex"");
    }

    function test_executes_order_against_swap() public {
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap();

        mockBalancerVaultCallsReturn(int256(sellAmount), -int256(buyAmount));

        vm.prank(solver);
        swap(encodedSwap);
    }

    function test_updates_the_filled_amount_to_be_the_full_sell_or_buy_amount() public {
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap();

        mockBalancerVaultCallsReturn(int256(sellAmount), -int256(buyAmount));

        vm.prank(solver);
        swap(encodedSwap);

        uint256 expectedFilledAmount = (kind == GPv2Order.KIND_SELL) ? sellAmount : buyAmount;
        assertEq(settlement.filledAmount(defaultOrderUid()), expectedFilledAmount);
    }

    function test_reverts_for_cancelled_orders() public {
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap();

        mockBalancerVaultCallsReturn(0, 0);

        vm.prank(trader.addr);
        settlement.invalidateOrder(defaultOrderUid());

        vm.prank(solver);
        vm.expectRevert("GPv2: order filled");
        swap(encodedSwap);
    }

    function test_reverts_for_partially_filled_orders() public {
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap();

        mockBalancerVaultCallsReturn(0, 0);

        vm.prank(trader.addr);
        settlement.setFilledAmount(defaultOrderUid(), 1);

        vm.prank(solver);
        vm.expectRevert("GPv2: order filled");
        swap(encodedSwap);
    }

    function test_reverts_when_not_exactly_trading_expected_amount() public {
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap();

        mockBalancerVaultCallsReturn(int256(sellAmount) - 1, -(int256(buyAmount) + 1));

        string memory kindString = (kind == GPv2Order.KIND_SELL) ? "sell" : "buy";
        vm.prank(solver);
        vm.expectRevert(bytes(string.concat("GPv2: ", kindString, " amount not respected")));
        swap(encodedSwap);
    }

    function test_reverts_when_specified_limit_amount_does_not_satisfy_expected_price() public {
        uint256 limitAmount = kind == GPv2Order.KIND_SELL
            ? buyAmount - 1 // receive slightly less buy token
            : sellAmount + 1; // pay slightly more sell token;
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap(limitAmount);

        mockBalancerVaultCallsReturn(int256(sellAmount), -int256(buyAmount));

        vm.prank(solver);
        vm.expectRevert(bytes((kind == GPv2Order.KIND_SELL) ? "GPv2: limit too low" : "GPv2: limit too high"));
        swap(encodedSwap);
    }

    function test_emits_a_trade_event() public {
        SwapEncoder.EncodedSwap memory encodedSwap = encodedDefaultSwap();

        uint256 executedSellAmount = sellAmount;
        uint256 executedBuyAmount = buyAmount;
        if (kind == GPv2Order.KIND_SELL) {
            executedBuyAmount = executedBuyAmount * 2;
        } else {
            executedSellAmount = executedSellAmount / 2;
        }
        mockBalancerVaultCallsReturn(int256(executedSellAmount), -int256(executedBuyAmount));

        vm.prank(solver);
        vm.expectEmit(address(settlement));
        emit GPv2Settlement.Trade({
            owner: trader.addr,
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: executedSellAmount,
            buyAmount: executedBuyAmount,
            feeAmount: encodedSwap.trade.feeAmount,
            orderUid: defaultOrderUid()
        });
        swap(encodedSwap);
    }
}

// solhint-disable-next-line no-empty-blocks
contract SellVariant is Variant(GPv2Order.KIND_SELL) {}

// solhint-disable-next-line no-empty-blocks
contract BuyVariant is Variant(GPv2Order.KIND_BUY) {}
