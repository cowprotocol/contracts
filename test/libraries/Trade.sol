// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Order} from "./Order.sol";
import {Sign} from "./Sign.sol";
import {GPv2Order, GPv2Signing, GPv2Trade, IERC20} from "src/contracts/mixins/GPv2Signing.sol";

library Trade {
    using GPv2Trade for uint256;
    using Order for Order.Flags;
    using Order for uint256;
    using Sign for GPv2Signing.Scheme;
    using Sign for uint256;

    error TokenIndexOutOfBounds();

    /// Trade flags
    struct Flags {
        Order.Flags flags;
        GPv2Signing.Scheme signingScheme;
    }

    /// @dev Given a `flags` struct, encode it into a uint256 for a GPv2Trade
    function toUint256(Flags memory flags) internal pure returns (uint256 encodedFlags) {
        encodedFlags |= flags.flags.toUint256();
        encodedFlags |= flags.signingScheme.toUint256();
    }

    /// @dev Given a GPv2Trade encoded flags, decode them into a `Flags` struct
    function toFlags(uint256 encodedFlags) internal pure returns (Flags memory flags) {
        flags.flags = encodedFlags.toFlags();
        flags.signingScheme = encodedFlags.toSigningScheme();
    }

    /// @dev Given a signature, executed amount and tokens, encode them into a GPv2Trade
    function toTrade(
        GPv2Order.Data memory order,
        uint256 sellTokenIndex,
        uint256 buyTokenIndex,
        Sign.Signature memory signature,
        uint256 executedAmount
    ) internal pure returns (GPv2Trade.Data memory trade) {
        trade = GPv2Trade.Data({
            sellTokenIndex: sellTokenIndex,
            buyTokenIndex: buyTokenIndex,
            receiver: order.receiver,
            sellAmount: order.sellAmount,
            buyAmount: order.buyAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: order.feeAmount,
            flags: toUint256(
                Flags({
                    flags: Order.Flags({
                        kind: order.kind,
                        sellTokenBalance: order.sellTokenBalance,
                        buyTokenBalance: order.buyTokenBalance,
                        partiallyFillable: order.partiallyFillable
                    }),
                    signingScheme: signature.scheme
                })
            ),
            executedAmount: executedAmount,
            signature: signature.data
        });
    }

    /// @dev Given a trade and tokens, encode them into a GPv2Order
    function toOrder(GPv2Trade.Data memory trade, IERC20[] memory tokens)
        internal
        pure
        returns (GPv2Order.Data memory)
    {
        if (trade.sellTokenIndex >= tokens.length || trade.buyTokenIndex >= tokens.length) {
            revert TokenIndexOutOfBounds();
        }

        Order.Flags memory flags = trade.flags.toFlags();

        return GPv2Order.Data({
            sellToken: tokens[trade.sellTokenIndex],
            buyToken: tokens[trade.buyTokenIndex],
            receiver: trade.receiver,
            sellAmount: trade.sellAmount,
            buyAmount: trade.buyAmount,
            validTo: trade.validTo,
            appData: trade.appData,
            feeAmount: trade.feeAmount,
            kind: flags.kind,
            sellTokenBalance: flags.sellTokenBalance,
            buyTokenBalance: flags.buyTokenBalance,
            partiallyFillable: flags.partiallyFillable
        });
    }
}
