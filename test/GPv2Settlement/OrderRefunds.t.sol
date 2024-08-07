// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

import {Helper} from "./Helper.sol";
import {Order} from "test/libraries/Order.sol";

enum FreeFunctionVariant {
    FreeFilledAmountStorage,
    FreePreSignatureStorage
}

abstract contract Variant is Helper {
    FreeFunctionVariant internal immutable freeFn;

    constructor(FreeFunctionVariant _freeFn) {
        freeFn = _freeFn;
    }

    function defaultOrderUids() internal view returns (bytes[] memory orderUids) {
        orderUids = new bytes[](3);
        orderUids[0] = Order.computeOrderUid(keccak256("order1"), trader.addr, 0);
        orderUids[1] = Order.computeOrderUid(keccak256("order2"), trader.addr, 0);
        orderUids[2] = Order.computeOrderUid(keccak256("order3"), trader.addr, 0);
    }

    function freeFunctionCall(bytes[] memory orderUids) private {
        if (freeFn == FreeFunctionVariant.FreeFilledAmountStorage) {
            settlement.freeFilledAmountStorage(orderUids);
        } else if (freeFn == FreeFunctionVariant.FreePreSignatureStorage) {
            settlement.freePreSignatureStorage(orderUids);
        } else {
            revert("Invalid free function");
        }
    }

    function freeFunctionCallTest(bytes[] memory orderUids) private {
        if (freeFn == FreeFunctionVariant.FreeFilledAmountStorage) {
            settlement.freeFilledAmountStorageTest(orderUids);
        } else if (freeFn == FreeFunctionVariant.FreePreSignatureStorage) {
            settlement.freePreSignatureStorageTest(orderUids);
        } else {
            revert("Invalid free function");
        }
    }

    function test_should_revert_if_not_called_from_an_interaction() public {
        bytes[] memory emptyOrderUids = new bytes[](0);

        vm.expectRevert("GPv2: not an interaction");
        freeFunctionCall(emptyOrderUids);
    }

    function test_should_revert_if_the_encoded_order_uid_are_malformed() public {
        bytes memory orderUidLt = new bytes(GPv2Order.UID_LENGTH - 1);
        bytes memory orderUidGt = new bytes(GPv2Order.UID_LENGTH + 1);

        checkInvalidLength(orderUidLt);
        checkInvalidLength(orderUidGt);
    }

    function test_should_revert_if_order_is_still_valid() public {
        bytes[] memory orderUids = new bytes[](1);
        orderUids[0] = Order.computeOrderUid(keccak256("order0"), trader.addr, type(uint32).max);

        vm.expectRevert("GPv2: order still valid");
        freeFunctionCallTest(orderUids);
    }

    function checkInvalidLength(bytes memory orderUid) private {
        bytes[] memory orderUids = new bytes[](1);
        orderUids[0] = orderUid;
        vm.expectRevert("GPv2: invalid uid");
        freeFunctionCallTest(orderUids);
    }
}

contract FreeFilledAmountStorage is Variant(FreeFunctionVariant.FreeFilledAmountStorage) {
    function test_should_set_filled_amount_to_0_for_all_orders() public {
        bytes[] memory orderUids = defaultOrderUids();

        for (uint256 i = 0; i < orderUids.length; i++) {
            vm.prank(trader.addr);
            settlement.invalidateOrder(orderUids[i]);
            assertEq(settlement.filledAmount(orderUids[i]), type(uint256).max, "filledAmount should be set to max");
        }

        settlement.freeFilledAmountStorageTest(orderUids);

        for (uint256 i = 0; i < orderUids.length; i++) {
            assertEq(settlement.filledAmount(orderUids[i]), 0, "filledAmount should be set to 0");
        }
    }
}

contract FreePreSignatureStorage is Variant(FreeFunctionVariant.FreePreSignatureStorage) {
    function test_should_clear_pre_signatures() public {
        bytes[] memory orderUids = defaultOrderUids();

        for (uint256 i = 0; i < orderUids.length; i++) {
            vm.prank(trader.addr);
            settlement.setPreSignature(orderUids[i], true);
            assertEq(
                settlement.preSignature(orderUids[i]),
                uint256(keccak256("GPv2Signing.Scheme.PreSign")),
                "preSignature not set"
            );
        }

        settlement.freePreSignatureStorageTest(orderUids);

        for (uint256 i = 0; i < orderUids.length; i++) {
            assertEq(settlement.preSignature(orderUids[i]), uint256(0), "preSignature should be set to 0");
        }
    }
}
