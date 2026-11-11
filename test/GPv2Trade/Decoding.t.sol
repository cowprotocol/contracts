// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";

import {Order as OrderLib, Sign as SignLib, Trade as TradeLib} from "test/libraries/Trade.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

/// @dev Port of the trade-related cases of the TypeScript `decoding` tests
/// (formerly `test/decoding.test.ts`) to Foundry, as part of the test
/// migration tracked in issue #126. The TypeScript tests asserted properties
/// of the off-chain decoding helpers in `src/ts`; these tests assert the same
/// properties against the on-chain decoding in `GPv2Trade`.
contract Decoding is Helper {
    using SettlementEncoder for SettlementEncoder.State;

    /// @dev Every valid combination of order flags and signing schemes: the
    /// Cartesian product of `Order.ALL_FLAGS()` (24 entries) and the four
    /// signing schemes, mirroring the combinations generated from
    /// `FLAG_MASKS` in the TypeScript tests.
    function allTradeFlags() private pure returns (TradeLib.Flags[] memory all) {
        OrderLib.Flags[] memory orderFlags = OrderLib.ALL_FLAGS();
        GPv2Signing.Scheme[4] memory schemes = SignLib.ALL_SIGNING_SCHEMES();
        all = new TradeLib.Flags[](orderFlags.length * schemes.length);
        uint256 offset = 0;
        for (uint256 i = 0; i < orderFlags.length; i++) {
            for (uint256 j = 0; j < schemes.length; j++) {
                all[offset] = TradeLib.Flags({flags: orderFlags[i], signingScheme: schemes[j]});
                offset++;
            }
        }
    }

    function assertSameFlags(TradeLib.Flags memory lhs, TradeLib.Flags memory rhs) private pure {
        assertEq(lhs.flags.kind, rhs.flags.kind);
        assertEq(lhs.flags.partiallyFillable, rhs.flags.partiallyFillable);
        assertEq(lhs.flags.sellTokenBalance, rhs.flags.sellTokenBalance);
        assertEq(lhs.flags.buyTokenBalance, rhs.flags.buyTokenBalance);
        assertEq(uint256(lhs.signingScheme), uint256(rhs.signingScheme));
    }

    /// @dev Mirrors "encodeTradeFlags is the right inverse of
    /// decodeTradeFlags": decoding an encoded flag combination returns the
    /// original combination, for every valid combination.
    function test_encoding_flags_is_the_right_inverse_of_decoding_flags() public view {
        TradeLib.Flags[] memory allFlags = allTradeFlags();
        for (uint256 i = 0; i < allFlags.length; i++) {
            TradeLib.Flags memory decoded = executor.extractFlagsStructuredTest(TradeLib.toUint256(allFlags[i]));
            assertSameFlags(decoded, allFlags[i]);
        }
    }

    /// @dev Mirrors "encodeTradeFlags is the left inverse of
    /// decodeTradeFlags": re-encoding a decoded valid flag value returns the
    /// original value, for every valid encoded value. The set of valid
    /// encoded values is the image of the valid flag combinations; note that
    /// the sell token balance encoding `0b01 << 2` only exists as a decode
    /// alias for ERC20 and is never produced by the encoder.
    function test_encoding_flags_is_the_left_inverse_of_decoding_flags() public view {
        TradeLib.Flags[] memory allFlags = allTradeFlags();
        for (uint256 i = 0; i < allFlags.length; i++) {
            uint256 encoded = TradeLib.toUint256(allFlags[i]);
            TradeLib.Flags memory decoded = executor.extractFlagsStructuredTest(encoded);
            assertEq(TradeLib.toUint256(decoded), encoded);
        }
    }

    /// @dev Mirrors the "sample order" case of the TypeScript `Trade` tests:
    /// encoding a trade with the settlement encoder and extracting the order
    /// back returns the original order. The order values are the exact
    /// sample values from the TypeScript test, where the token and receiver
    /// addresses are `fillBytes(20, 0x01)`, `fillBytes(20, 0x02)` and
    /// `fillBytes(20, 0x03)` respectively.
    function test_should_decode_the_sample_order_from_an_encoded_trade() public {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(0x0101010101010101010101010101010101010101),
            buyToken: IERC20(0x0202020202020202020202020202020202020202),
            receiver: 0x0303030303030303030303030303030303030303,
            sellAmount: 42 ether,
            buyAmount: 13.37 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_BUY,
            partiallyFillable: true,
            sellTokenBalance: GPv2Order.BALANCE_EXTERNAL,
            buyTokenBalance: GPv2Order.BALANCE_INTERNAL
        });

        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.EthSign, 42);

        GPv2Order.Data memory extractedOrder = executor.extractOrderTest(encoder.tokens(), encoder.trades[0]);
        assertEq(abi.encode(extractedOrder), abi.encode(order));
    }
}
