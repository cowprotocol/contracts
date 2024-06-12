// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20, GPv2Order, GPv2Trade, GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";
import {Sign} from "./Sign.sol";
import {Order} from "./Order.sol";

library Trade {
    using GPv2Trade for uint256;
    using Order for Order.Flags;
    using Order for uint256;
    using Sign for GPv2Signing.Scheme;
    using Sign for uint256;

    error TokenIndexOutOfBounds();
    error TokenNotFound();

    /// Trade flags
    struct Flags {
        Order.Flags flags;
        GPv2Signing.Scheme signingScheme;
    }

    function toUint256(Flags memory flags) internal pure returns (uint256 encodedFlags) {
        encodedFlags |= flags.flags.toUint256();
        encodedFlags |= flags.signingScheme.toUint256();
    }

    function toFlags(uint256 encodedFlags) internal pure returns (Flags memory flags) {
        flags.flags = encodedFlags.toFlags();
        flags.signingScheme = encodedFlags.toSigningScheme();
    }

    function toTrade(
        GPv2Order.Data memory order,
        IERC20[] memory tokens,
        Sign.Signature memory signature,
        uint256 executedAmount
    ) internal pure returns (GPv2Trade.Data memory trade) {
        trade = GPv2Trade.Data({
            sellTokenIndex: findTokenIndex(order.sellToken, tokens),
            buyTokenIndex: findTokenIndex(order.buyToken, tokens),
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

    function findTokenIndex(IERC20 token, IERC20[] memory tokens) private pure returns (uint256) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }
        revert TokenNotFound();
    }
}
