// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

import {GPv2Settlement, Helper} from "./Helper.sol";

//solhint-disable func-name-mixedcase
contract InvalidateOrder is Helper {
    using GPv2Order for bytes;

    function test_sets_filled_amount_of_the_callers_order_to_max_uint256() public {
        bytes32 orderDigest = keccak256("some order");
        uint32 validTo = type(uint32).max;

        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderDigest, trader.addr, validTo);

        vm.prank(trader.addr);
        settlement.invalidateOrder(orderUid);
        assertEq(settlement.filledAmount(orderUid), type(uint256).max);
    }

    function test_emits_an_order_invalidated_event() public {
        bytes32 orderDigest = keccak256("some order");
        uint32 validTo = type(uint32).max;

        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderDigest, trader.addr, validTo);

        vm.prank(trader.addr);
        vm.expectEmit(address(settlement));
        emit GPv2Settlement.OrderInvalidated(trader.addr, orderUid);
        vm.recordLogs();
        settlement.invalidateOrder(orderUid);
    }

    function test_reverts_when_invalidating_an_order_that_does_not_belong_to_the_caller() public {
        bytes32 orderDigest = keccak256("some order");
        uint32 validTo = type(uint32).max;

        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(orderDigest, makeAddr("not-trader"), validTo);

        vm.expectRevert("GPv2: caller does not own order");
        settlement.invalidateOrder(orderUid);
    }
}
