// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

import {Helper} from "./Helper.sol";

contract PackOrderUidParams is Helper {
    function test_packOrderUidParams_packs_the_order_UID() public view {
        bytes32 orderDigest = keccak256("order digest");
        address owner = address(uint160(uint256(keccak256("owner"))));
        uint32 validTo = uint32(uint256(keccak256("valid to")));
        assertEq(
            executor.packOrderUidParamsTest(GPv2Order.UID_LENGTH, orderDigest, owner, validTo),
            abi.encodePacked(orderDigest, owner, validTo)
        );
    }

    function test_reverts_if_the_buffer_length_is_wrong() public {
        vm.expectRevert("GPv2: uid buffer overflow");
        executor.packOrderUidParamsTest(GPv2Order.UID_LENGTH + 1, bytes32(0), address(0), uint32(0));
    }
}
