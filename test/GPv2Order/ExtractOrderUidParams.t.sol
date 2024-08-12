// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

import {Helper} from "./Helper.sol";

contract ExtractOrderUidParams is Helper {
    function test_round_trip_encode_decode() public view {
        bytes32 orderDigest = keccak256("order digest");
        address owner = address(uint160(uint256(keccak256("owner"))));
        uint32 validTo = uint32(uint256(keccak256("valid to")));
        bytes memory orderUid = executor.packOrderUidParamsTest(GPv2Order.UID_LENGTH, orderDigest, owner, validTo);

        (bytes32 extractedOrderDigest, address extractedOwner, uint32 extractedValidTo) =
            executor.extractOrderUidParamsTest(orderUid);
        assertEq(extractedOrderDigest, orderDigest);
        assertEq(extractedOwner, owner);
        assertEq(extractedValidTo, validTo);
    }

    function test_reverts_with_uid_longer_than_expected() public {
        vm.expectRevert("GPv2: invalid uid");
        executor.extractOrderUidParamsTest(new bytes(GPv2Order.UID_LENGTH + 1));
    }

    function test_reverts_with_uid_shorter_than_expected() public {
        vm.expectRevert("GPv2: invalid uid");
        executor.extractOrderUidParamsTest(new bytes(GPv2Order.UID_LENGTH - 1));
    }
}
