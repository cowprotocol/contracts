// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";

import {Order} from "./Order.sol";

library OrderFuzz {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;
    using GPv2Trade for uint256;

    struct Params {
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

    function order(Params memory params) internal pure returns (GPv2Order.Data memory) {
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
