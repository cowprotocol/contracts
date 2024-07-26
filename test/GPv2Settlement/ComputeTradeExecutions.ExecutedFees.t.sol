// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {BaseComputeTradeExecutions, GPv2Order, SettlementEncoder} from "./ComputeTradeExecutions.t.sol";

contract OrderExecutedFees is BaseComputeTradeExecutions {
    using GPv2Order for GPv2Order.Data;
    using SettlementEncoder for SettlementEncoder.State;

    function test_should_add_full_fee_for_fill_or_kill_sell_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.feeAmount = 10 ether;

        (uint256 executedSellAmount,) = computeSettlementForOrder(order);
        assertEq(executedSellAmount, order.sellAmount + order.feeAmount);
    }

    function test_should_add_full_fee_for_fill_or_kill_buy_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.feeAmount = 10 ether;

        uint256 expectedSellAmount = order.buyAmount * buyPrice / sellPrice;
        (uint256 executedSellAmount,) = computeSettlementForOrder(order);
        assertEq(executedSellAmount, expectedSellAmount + order.feeAmount);
    }

    function test_should_add_portion_of_fees_for_partially_filled_sell_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;
        order.feeAmount = 10 ether;
        executedAmount = order.sellAmount / 3;
        uint256 executedFee = order.feeAmount / 3;

        (uint256 executedSellAmount,) = computeSettlementForOrder(order);
        assertEq(executedSellAmount, executedAmount + executedFee);
    }

    function test_should_add_portion_of_fees_for_partially_filled_buy_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = true;
        order.feeAmount = 10 ether;
        executedAmount = order.buyAmount / 4;
        uint256 executedFee = order.feeAmount / 4;

        (uint256 executedSellAmount, uint256 executedBuyAmount) = computeSettlementForOrder(order);
        uint256 expectedSellAmount = executedBuyAmount * buyPrice / sellPrice;
        assertEq(executedSellAmount, expectedSellAmount + executedFee);
    }
}
