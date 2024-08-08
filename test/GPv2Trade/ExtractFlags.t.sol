// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";

import {Order as OrderLib, Trade as TradeLib} from "test/libraries/Trade.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

contract ExtractOrder is Helper {
    using SettlementEncoder for SettlementEncoder.State;

    function test_should_extract_all_supported_order_flags() public view {
        OrderLib.Flags[] memory flags = OrderLib.ALL_FLAGS();

        for (uint256 i = 0; i < flags.length; i++) {
            OrderLib.Flags memory extractedFlags =
                executor.extractFlagsStructuredTest(OrderLib.toUint256(flags[i])).flags;
            assertEq(extractedFlags.kind, flags[i].kind);
            assertEq(extractedFlags.partiallyFillable, flags[i].partiallyFillable);
            assertEq(extractedFlags.sellTokenBalance, flags[i].sellTokenBalance);
            assertEq(extractedFlags.buyTokenBalance, flags[i].buyTokenBalance);
        }
    }

    function test_should_accept_0b00_and_0b01_for_ERC20_sell_token_balance_flag() public view {
        uint256 sellTokenBalanceOffset = 2;
        OrderLib.Flags memory flags0b00 = executor.extractFlagsStructuredTest(0 << sellTokenBalanceOffset).flags;
        assertEq(flags0b00.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        OrderLib.Flags memory flags0b01 = executor.extractFlagsStructuredTest(1 << sellTokenBalanceOffset).flags;
        assertEq(flags0b01.sellTokenBalance, GPv2Order.BALANCE_ERC20);
    }

    function test_should_extract_all_supported_signing_schemes() public view {
        GPv2Signing.Scheme[4] memory schemes = TradeLib.ALL_SIGNING_SCHEMES();
        for (uint256 i = 0; i < schemes.length; i++) {
            TradeLib.Flags memory flags = TradeLib.Flags({
                signingScheme: schemes[i],
                // Any value works here, using 0 for simplicity.
                flags: OrderLib.toFlags(0)
            });
            TradeLib.Flags memory extractedFlags = executor.extractFlagsStructuredTest(TradeLib.toUint256(flags));
            assertEq(uint256(extractedFlags.signingScheme), uint256(flags.signingScheme));
        }
    }

    function test_should_revert_when_encoding_invalid_flags() public {
        // TODO: once Foundry supports catching Solidity low-level errors,
        // require that this reverts with "failed to convert value into enum
        // type".
        // Track support at https://github.com/foundry-rs/foundry/issues/4012
        vm.expectRevert();
        executor.extractFlagsStructuredTest(1 << 7);
    }
}
