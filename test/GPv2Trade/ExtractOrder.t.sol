// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";

import {Order as OrderLib} from "test/libraries/Order.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

contract ExtractOrder is Helper {
    using SettlementEncoder for SettlementEncoder.State;

    struct Fuzzed {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 executedAmount;
    }

    function sampleOrder() private returns (GPv2Order.Data memory order) {
        order = GPv2Order.Data({
            sellToken: IERC20(makeAddr("GPv2Trade.ExtractOrder sampleOrder sell token")),
            buyToken: IERC20(makeAddr("GPv2Trade.ExtractOrder sampleOrder buy token")),
            receiver: makeAddr("GPv2Trade.ExtractOrder sampleOrder receiver"),
            sellAmount: 42 ether,
            buyAmount: 13.37 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    function assertSameOrder(GPv2Order.Data memory lhs, GPv2Order.Data memory rhs) private pure {
        assertEq(abi.encode(lhs), abi.encode(rhs));
    }

    function testFuzz_should_round_trip_encode_order_data(Fuzzed memory fuzzed) public {
        OrderLib.Flags[] memory flags = OrderLib.ALL_FLAGS();

        for (uint256 i = 0; i < flags.length; i++) {
            GPv2Order.Data memory order = GPv2Order.Data({
                sellToken: IERC20(fuzzed.sellToken),
                buyToken: IERC20(fuzzed.buyToken),
                receiver: fuzzed.receiver,
                sellAmount: fuzzed.sellAmount,
                buyAmount: fuzzed.buyAmount,
                validTo: fuzzed.validTo,
                appData: fuzzed.appData,
                feeAmount: fuzzed.feeAmount,
                kind: flags[i].kind,
                partiallyFillable: flags[i].partiallyFillable,
                sellTokenBalance: flags[i].sellTokenBalance,
                buyTokenBalance: flags[i].buyTokenBalance
            });

            SettlementEncoder.State storage encoder = SettlementEncoder.makeSettlementEncoder();
            encoder.signEncodeTrade(
                vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, fuzzed.executedAmount
            );
            GPv2Order.Data memory extractedOrder = executor.extractOrderTest(encoder.tokens(), encoder.trades[0]);
            assertSameOrder(order, extractedOrder);
        }
    }

    function should_revert_for_invalid_token_indices(GPv2Order.Data memory order, IERC20[] memory tokens) internal {
        SettlementEncoder.State storage encoder = SettlementEncoder.makeSettlementEncoder();
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 0);
        // TODO: once Foundry supports catching EVM errors, require that this
        // reverts with "array out-of-bounds access".
        // Track support at https://github.com/foundry-rs/foundry/issues/4012
        vm.expectRevert();
        executor.extractOrderTest(tokens, encoder.trades[0]);
    }

    function test_should_revert_for_invalid_sell_token_indices() public {
        GPv2Order.Data memory order = sampleOrder();
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = order.buyToken;
        should_revert_for_invalid_token_indices(order, tokens);
    }

    function test_should_revert_for_invalid_buy_token_indices() public {
        GPv2Order.Data memory order = sampleOrder();
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = order.sellToken;
        should_revert_for_invalid_token_indices(order, tokens);
    }
}
