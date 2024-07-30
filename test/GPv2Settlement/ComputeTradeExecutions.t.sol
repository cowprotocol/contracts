// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {GPv2Settlement} from "src/contracts/GPv2Settlement.sol";
import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {GPv2Transfer, Helper, SettlementEncoder} from "./Helper.sol";

import {Order} from "test/libraries/Order.sol";
import {Registry, TokenRegistry} from "test/libraries/encoders/TokenRegistry.sol";

abstract contract BaseComputeTradeExecutions is Helper {
    using TokenRegistry for TokenRegistry.State;
    using TokenRegistry for Registry;
    using SettlementEncoder for SettlementEncoder.State;

    IERC20 internal sellToken;
    IERC20 internal buyToken;

    uint256 internal executedAmount = 10 ether;
    uint256 internal sellPrice = 1;
    uint256 internal buyPrice = 2;

    function setUp() public virtual override {
        super.setUp();

        sellToken = IERC20(makeAddr("GPv2Settlement.BaseComputeTradeExecutions: sellToken"));
        buyToken = IERC20(makeAddr("GPv2Settlement.BaseComputeTradeExecutions: buyToken"));
    }

    function defaultOrder() internal view returns (GPv2Order.Data memory) {
        return GPv2Order.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount: 42 ether,
            buyAmount: 13.37 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 0,
            kind: bytes32(0),
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    function computeSettlementForOrder(GPv2Order.Data memory order)
        internal
        returns (uint256 executedSellAmount, uint256 executedBuyAmount)
    {
        encoder.tokenRegistry.tokenRegistry().setPrice(sellToken, sellPrice);
        encoder.tokenRegistry.tokenRegistry().setPrice(buyToken, buyPrice);
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, executedAmount);

        SettlementEncoder.EncodedSettlement memory encoded = encoder.encode(settlement);
        (GPv2Transfer.Data[] memory inTransfers, GPv2Transfer.Data[] memory outTransfers) =
            settlement.computeTradeExecutionsTest(encoded.tokens, encoded.clearingPrices, encoded.trades);

        // As `vm.expectRevert` may be used prior to this function, `computeTradeExecutionsTest` may revert however
        // execution within this function will still continue. This is a workaround to prevent the panic.
        if (inTransfers.length != 0 && outTransfers.length != 0) {
            executedSellAmount = inTransfers[0].amount;
            executedBuyAmount = outTransfers[0].amount;
        }
    }
}

contract ComputeTradeExecutions is BaseComputeTradeExecutions {
    using TokenRegistry for TokenRegistry.State;
    using TokenRegistry for Registry;
    using SettlementEncoder for SettlementEncoder.State;
    using Order for GPv2Order.Data;

    function test_should_not_allocate_additional_memory() public {
        assertEq(settlement.computeTradeExecutionMemoryTest(), 0);
    }

    function test_should_compute_in_out_transfers_for_multiple_trades() public {
        uint256 tradeCount = 10;
        for (uint256 i = 0; i < tradeCount; i++) {
            GPv2Order.Data memory order = defaultOrder();
            order.kind = GPv2Order.KIND_BUY;
            order.partiallyFillable = true;
            encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 0.7734 ether);
        }

        encoder.tokenRegistry.tokenRegistry().setPrice(sellToken, sellPrice);
        encoder.tokenRegistry.tokenRegistry().setPrice(buyToken, buyPrice);
        SettlementEncoder.EncodedSettlement memory encoded = encoder.encode(settlement);
        (GPv2Transfer.Data[] memory inTransfer, GPv2Transfer.Data[] memory outTransfer) =
            settlement.computeTradeExecutionsTest(encoded.tokens, encoded.clearingPrices, encoded.trades);

        assertEq(inTransfer.length, tradeCount);
        assertEq(outTransfer.length, tradeCount);
    }

    function test_revert_if_the_order_is_expired() public {
        // set an explicit block timestamp as otherwise order.validTo will
        // not be distinguishable from a default initialised uint32 (0) due
        // block.timestamp being equal to 1 here in the test environment
        vm.warp(42);

        GPv2Order.Data memory order = defaultOrder();
        order.validTo = uint32(block.timestamp - 1);
        order.kind = GPv2Order.KIND_SELL;

        vm.expectRevert("GPv2: order expired");
        computeSettlementForOrder(order);
    }

    function test_revert_if_limit_price_not_respected() public {
        sellPrice = 1;
        buyPrice = 1000;

        GPv2Order.Data memory order = defaultOrder();
        order.sellAmount = 100 ether;
        order.buyAmount = 1 ether;
        order.kind = GPv2Order.KIND_SELL;

        assertLt(order.sellAmount * sellPrice, order.buyAmount * buyPrice, "Incorrect test setup");

        vm.expectRevert("GPv2: limit price not respected");
        computeSettlementForOrder(order);
    }

    function test_does_not_revert_if_clearing_price_exactly_at_limit_price() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;

        sellPrice = order.buyAmount;
        buyPrice = order.sellAmount;
        (, uint256 executedBuyAmount) = computeSettlementForOrder(order);
        assertEq(executedBuyAmount, order.buyAmount);
    }

    function test_should_ignore_executed_trade_amount_for_fill_or_kill_orders() public {
        GPv2Order.Data memory order = defaultOrder();
        order.partiallyFillable = false;
        order.kind = GPv2Order.KIND_BUY;
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 10 ether);

        order.appData = keccak256("another-order");
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 100 ether);

        encoder.tokenRegistry.tokenRegistry().setPrice(sellToken, sellPrice);
        encoder.tokenRegistry.tokenRegistry().setPrice(buyToken, buyPrice);
        SettlementEncoder.EncodedSettlement memory encoded = encoder.encode(settlement);
        (GPv2Transfer.Data[] memory inTransfers,) =
            settlement.computeTradeExecutionsTest(encoded.tokens, encoded.clearingPrices, encoded.trades);

        assertEq(inTransfers[0].amount, inTransfers[1].amount);
    }

    function test_should_emit_a_trade_event() public {
        GPv2Order.Data memory order = defaultOrder();
        order.kind = GPv2Order.KIND_SELL;
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 0);
        encoder.tokenRegistry.tokenRegistry().setPrice(sellToken, sellPrice);
        encoder.tokenRegistry.tokenRegistry().setPrice(buyToken, buyPrice);
        SettlementEncoder.EncodedSettlement memory encoded = encoder.encode(settlement);

        uint256 executedSellAmount = order.sellAmount + order.feeAmount;
        uint256 executedBuyAmount = order.sellAmount * sellPrice / buyPrice;
        vm.expectEmit(address(settlement));
        emit GPv2Settlement.Trade(
            trader.addr,
            order.sellToken,
            order.buyToken,
            executedSellAmount,
            executedBuyAmount,
            order.feeAmount,
            order.computeOrderUid(domainSeparator, trader.addr)
        );
        // We record logs to assert that there was only one emitted event
        vm.recordLogs();
        settlement.computeTradeExecutionsTest(encoded.tokens, encoded.clearingPrices, encoded.trades);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
    }
}
