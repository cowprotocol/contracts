// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2Settlement} from "src/contracts/GPv2Settlement.sol";
import {Harness} from "test/GPv2Settlement/Helper.sol";
import {SettlementEncoder} from "./encoders/SettlementEncoder.sol";
import {SwapEncoder} from "./encoders/SwapEncoder.sol";

library Settlement {
    function settle(GPv2Settlement settler, SettlementEncoder.EncodedSettlement memory settlement) internal {
        settler.settle(settlement.tokens, settlement.clearingPrices, settlement.trades, settlement.interactions);
    }

    function swap(GPv2Settlement settler, SwapEncoder.EncodedSwap memory _swap) internal {
        settler.swap(_swap.swaps, _swap.tokens, _swap.trade);
    }
}
