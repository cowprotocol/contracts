// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20, GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
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
}
