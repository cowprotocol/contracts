// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

import {Helper} from "./Helper.sol";

// solhint-disable func-name-mixedcase
contract FilledAmount is Helper {
    using GPv2Order for bytes;

    function test_filledAmount_is_zero_for_untouched_order() public view {
        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(bytes32(0), address(0), type(uint32).max);
        assertEq(settlement.filledAmount(orderUid), 0);
    }
}
