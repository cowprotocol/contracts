// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {BaseComputeTradeExecutions, GPv2Order, SettlementEncoder} from "./ComputeTradeExecutions.t.sol";

contract OrderExecutedAmounts is BaseComputeTradeExecutions {
    using GPv2Order for GPv2Order.Data;
    using SettlementEncoder for SettlementEncoder.State;

    function test_should_compute_amounts_for_fill_or_kill_sell_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = false;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);

        assertEq(executedSellAmount, order.sellAmount);
        assertEq(executedBuyAmount, order.sellAmount * sellPrice / buyPrice);
    }

    function test_should_respect_limit_price_for_fill_or_kill_sell_order() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = false;

        (, uint256 executedBuyAmount) = computeSettlementForOrder(order);
        assertGt(executedBuyAmount, order.buyAmount);
    }

    function test_should_compute_amounts_for_fill_or_kill_buy_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = false;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);

        assertEq(executedSellAmount, order.buyAmount * buyPrice / sellPrice);
        assertEq(executedBuyAmount, order.buyAmount);
    }

    function test_should_respect_limit_price_for_fill_or_kill_buy_order() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = false;

        (uint256 executedSellAmount,) = computeSettlementForOrder(order);
        assertLt(executedSellAmount, order.sellAmount);
    }

    function test_should_compute_amounts_for_partially_fillable_sell_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);

        assertEq(executedSellAmount, executedAmount);
        assertEq(executedBuyAmount, executedAmount * sellPrice / buyPrice);
    }

    function test_should_respect_limit_price_for_partially_fillable_sell_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);
        assertGt(executedBuyAmount * order.sellAmount, executedSellAmount * order.buyAmount);
    }

    function test_should_compute_amounts_for_partially_fillable_buy_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = true;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);

        assertEq(executedSellAmount, executedAmount * buyPrice / sellPrice);
        assertEq(executedBuyAmount, executedAmount);
    }

    function test_should_respect_limit_price_for_partially_fillable_buy_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = true;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);
        assertGt(executedBuyAmount * order.sellAmount, executedSellAmount * order.buyAmount);
    }

    function test_should_round_executed_buy_amount_in_favour_of_trader_for_partial_fill_sell_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;
        order.sellAmount = 100 ether;
        order.buyAmount = 1 ether;

        executedAmount = 1;
        sellPrice = 1;
        buyPrice = 100;

        (, uint256 executedBuyAmount) = computeSettlementForOrder(order);
        // NOTE: Buy token is 100x more valuable than the sell token, however,
        // selling just 1 atom of the less valuable token will still give the
        // trader 1 atom of the much more valuable buy token.
        assertEq(executedBuyAmount, 1);
    }

    function test_should_round_executed_sell_amount_in_favour_of_trader_for_partial_fill_buy_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = true;
        order.sellAmount = 1 ether;
        order.buyAmount = 100 ether;

        executedAmount = 1;
        sellPrice = 100;
        buyPrice = 1;

        (uint256 executedSellAmount,) = computeSettlementForOrder(order);
        // NOTE: Sell token is 100x more valuable than the buy token. Buying
        // just 1 atom of the less valuable buy token is free for the trader.
        assertEq(executedSellAmount, 0);
    }

    function test_revert_if_order_is_executed_for_too_large_amount_sell_order() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;
        executedAmount = order.sellAmount + 1;

        vm.expectRevert("GPv2: order filled");
        computeSettlementForOrder(order);
    }

    function test_revert_if_order_is_executed_for_too_large_amount_sell_order_partially_filled() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;

        // initial executed amount
        executedAmount = order.sellAmount / 2;
        assertNotEq(executedAmount, 0, "Incorrect test setup");

        computeSettlementForOrder(order);

        // Refresh the encoder to clear the previous state - and reset the token prices
        encoder = SettlementEncoder.makeSettlementEncoder();

        uint256 unfilledAmount = order.sellAmount - executedAmount;
        assertNotEq(unfilledAmount, 0, "Incorrect test setup");
        executedAmount = unfilledAmount + 1;

        vm.expectRevert("GPv2: order filled");
        computeSettlementForOrder(order);
    }

    function test_revert_if_order_is_executed_for_too_large_amount_buy_order() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = true;
        executedAmount = order.buyAmount + 1;

        vm.expectRevert("GPv2: order filled");
        computeSettlementForOrder(order);
    }
}
