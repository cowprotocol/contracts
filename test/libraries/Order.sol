// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";

library Order {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;
    using GPv2Trade for uint256;

    /// Order flags
    struct Flags {
        bytes32 kind;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
        bool partiallyFillable;
    }

    /// All parameters needed to generated a valid fuzzed order.
    struct Fuzzed {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 flagsPick;
    }

    // I wish I could declare the following as constants and export them as part
    // of the library. However, "Only constants of value type and byte array
    // type are implemented." and "Library cannot have non-constant state
    // variables". So I'm left with defining them as functions.

    function ALL_KINDS() internal pure returns (bytes32[2] memory) {
        return [GPv2Order.KIND_SELL, GPv2Order.KIND_BUY];
    }

    function ALL_SELL_TOKEN_BALANCES() internal pure returns (bytes32[3] memory) {
        return [GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_INTERNAL];
    }

    function ALL_BUY_TOKEN_BALANCES() internal pure returns (bytes32[2] memory) {
        return [GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_INTERNAL];
    }

    function ALL_FLAGS() internal pure returns (Flags[] memory out) {
        uint256 numBools = 1;
        uint256 boolLength = 2;
        // "out" has as many entries as there are distinct options to fill the
        // `Flags` struct.
        out = new Flags[](
            ALL_KINDS().length * ALL_SELL_TOKEN_BALANCES().length * ALL_BUY_TOKEN_BALANCES().length
                * (boolLength * numBools)
        );
        uint256 offset = 0;
        for (uint256 kindI = 0; kindI < ALL_KINDS().length; kindI++) {
            for (
                uint256 sellTokenBalanceI = 0; sellTokenBalanceI < ALL_SELL_TOKEN_BALANCES().length; sellTokenBalanceI++
            ) {
                for (
                    uint256 buyTokenBalanceI = 0; buyTokenBalanceI < ALL_BUY_TOKEN_BALANCES().length; buyTokenBalanceI++
                ) {
                    bytes32 kind = ALL_KINDS()[kindI];
                    bytes32 sellTokenBalance = ALL_SELL_TOKEN_BALANCES()[sellTokenBalanceI];
                    bytes32 buyTokenBalance = ALL_BUY_TOKEN_BALANCES()[buyTokenBalanceI];
                    out[offset] = Flags({
                        kind: kind,
                        sellTokenBalance: sellTokenBalance,
                        buyTokenBalance: buyTokenBalance,
                        partiallyFillable: false
                    });
                    out[offset + 1] = Flags({
                        kind: kind,
                        sellTokenBalance: sellTokenBalance,
                        buyTokenBalance: buyTokenBalance,
                        partiallyFillable: true
                    });
                    offset += 2;
                }
            }
        }
        // Sanity check: we filled all array slots.
        require(offset == out.length, "undefined entries in flag array");
    }

    /// @dev Return an empty sell order
    function emptySell() internal pure returns (GPv2Order.Data memory order) {
        order.sellToken = IERC20(address(0));
        order.buyToken = IERC20(address(0));
        order.receiver = address(0);
        order.sellAmount = 0;
        order.buyAmount = 0;
        order.validTo = 0;
        order.appData = bytes32(0);
        order.feeAmount = 0;
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = false; // fill-or-kill
        order.sellTokenBalance = GPv2Order.BALANCE_ERC20;
        order.buyTokenBalance = GPv2Order.BALANCE_ERC20;
    }

    /// @dev Given a `flags` struct, encode it into a uint256 for a GPv2Trade
    function toUint256(Flags memory flags) internal pure returns (uint256 encodedFlags) {
        // GPv2Order.KIND_SELL = 0 (default)
        if (flags.kind == GPv2Order.KIND_BUY) {
            encodedFlags |= 1 << 0;
        } else if (flags.kind != GPv2Order.KIND_SELL) {
            revert("Invalid order kind");
        }

        // Partially fillable = 0 (default) - ie. fill-or-kill
        if (flags.partiallyFillable) {
            encodedFlags |= 1 << 1;
        }

        // ERC20 sellTokenBalance = 0 (default; 1 << 2 has the same effect)
        if (flags.sellTokenBalance == GPv2Order.BALANCE_EXTERNAL) {
            encodedFlags |= 2 << 2;
        } else if (flags.sellTokenBalance == GPv2Order.BALANCE_INTERNAL) {
            encodedFlags |= 3 << 2;
        } else if (flags.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert("Invalid sell token balance");
        }

        // ERC20 buyTokenBalance = 0 (default)
        if (flags.buyTokenBalance == GPv2Order.BALANCE_INTERNAL) {
            encodedFlags |= 1 << 4;
        } else if (flags.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert("Invalid buy token balance");
        }
    }

    /// @dev Given a GPv2Trade encoded flags, decode them into a `Flags` struct
    function toFlags(uint256 encodedFlags) internal pure returns (Flags memory flags) {
        (flags.kind, flags.partiallyFillable, flags.sellTokenBalance, flags.buyTokenBalance,) =
            encodedFlags.extractFlags();
    }

    /// @dev Computes the order UID for an order and the given owner
    function computeOrderUid(GPv2Order.Data memory order, bytes32 domainSeparator, address owner)
        internal
        pure
        returns (bytes memory)
    {
        return computeOrderUid(order.hash(domainSeparator), owner, order.validTo);
    }

    /// @dev Computes the order UID for its base components
    function computeOrderUid(bytes32 orderHash, address owner, uint32 validTo)
        internal
        pure
        returns (bytes memory orderUid)
    {
        orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderHash, owner, validTo);
    }

    function fuzz(Fuzzed memory params) internal pure returns (GPv2Order.Data memory) {
        Order.Flags[] memory allFlags = Order.ALL_FLAGS();
        // `flags` isn't exactly random, but for fuzzing purposes it should be
        // more than enough.
        Order.Flags memory flags = allFlags[uint256(params.flagsPick) % allFlags.length];
        return GPv2Order.Data({
            sellToken: IERC20(params.sellToken),
            buyToken: IERC20(params.buyToken),
            receiver: params.receiver,
            sellAmount: params.sellAmount,
            buyAmount: params.buyAmount,
            validTo: params.validTo,
            appData: params.appData,
            feeAmount: params.feeAmount,
            partiallyFillable: flags.partiallyFillable,
            kind: flags.kind,
            sellTokenBalance: flags.sellTokenBalance,
            buyTokenBalance: flags.buyTokenBalance
        });
    }
}
