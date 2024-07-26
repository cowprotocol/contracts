// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {BaseComputeTradeExecutions, GPv2Order, SettlementEncoder} from "./ComputeTradeExecutions.t.sol";
import {Order} from "test/libraries/Order.sol";

contract OrderFilledAmounts is BaseComputeTradeExecutions {
    using GPv2Order for GPv2Order.Data;
    using Order for GPv2Order.Data;
    using SettlementEncoder for SettlementEncoder.State;

    function test_should_fill_full_sell_amount_for_fill_or_kill_sell_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_SELL;
        computeSettlementForOrder(order);

        bytes memory orderUid = order.computeOrderUid(domainSeparator, trader.addr);
        assertEq(settlement.filledAmount(orderUid), order.sellAmount);
    }

    function test_should_fill_full_buy_amount_for_fill_or_kill_buy_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_BUY;
        computeSettlementForOrder(order);

        bytes memory orderUid = order.computeOrderUid(domainSeparator, trader.addr);
        assertEq(settlement.filledAmount(orderUid), order.buyAmount);
    }

    function test_should_fill_executed_amount_for_partially_filled_sell_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = true;
        executedAmount = order.sellAmount / 3;
        computeSettlementForOrder(order);

        bytes memory orderUid = order.computeOrderUid(domainSeparator, trader.addr);
        assertEq(settlement.filledAmount(orderUid), executedAmount);
    }

    function test_should_fill_executed_amount_for_partially_filled_buy_orders() public {
        GPv2Order.Data memory order = partialOrder();
        order.kind = GPv2Order.KIND_BUY;
        order.partiallyFillable = true;
        executedAmount = order.buyAmount / 4;
        computeSettlementForOrder(order);

        bytes memory orderUid = order.computeOrderUid(domainSeparator, trader.addr);
        assertEq(settlement.filledAmount(orderUid), executedAmount);
    }
}
