// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";
import {Order} from "test/libraries/Order.sol";
import {Sign} from "test/libraries/Sign.sol";

contract SetPreSignature is Helper {
    address private immutable owner = makeAddr("GPv2Signing.SetPreSignature owner");
    bytes private orderUid =
        Order.computeOrderUid(keccak256("GPv2Signing.SetPreSignature order hash"), owner, type(uint32).max);

    function test_should_set_the_pre_signature() public {
        vm.prank(owner);
        executor.setPreSignature(orderUid, true);
        assertEq(executor.preSignature(orderUid), Sign.PRE_SIGNED);
    }

    function test_should_unset_the_pre_signature() public {
        vm.prank(owner);
        executor.setPreSignature(orderUid, true);
        vm.prank(owner);
        executor.setPreSignature(orderUid, false);
        assertEq(executor.preSignature(orderUid), 0);
    }

    function test_should_emit_a_pre_signature_event() public {
        vm.prank(owner);
        vm.expectEmit(address(executor));
        emit GPv2Signing.PreSignature(owner, orderUid, true);
        executor.setPreSignature(orderUid, true);

        vm.prank(owner);
        vm.expectEmit(address(executor));
        emit GPv2Signing.PreSignature(owner, orderUid, false);
        executor.setPreSignature(orderUid, false);
    }

    function test_should_emit_a_PreSignature_event_even_if_storage_does_not_change() public {
        vm.prank(owner);
        executor.setPreSignature(orderUid, true);
        vm.prank(owner);
        vm.expectEmit(address(executor));
        emit GPv2Signing.PreSignature(owner, orderUid, true);
        executor.setPreSignature(orderUid, true);
    }

    function test_reverts_if_the_order_owner_is_not_the_transaction_sender() public {
        vm.expectRevert("GPv2: cannot presign order");
        executor.setPreSignature(orderUid, true);
    }
}
