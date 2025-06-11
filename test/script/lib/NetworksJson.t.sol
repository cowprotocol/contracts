// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {NetworksJson} from "script/lib/NetworksJson.sol";

contract TestTransferOwnership is Test {
    NetworksJson private networksJson;

    function setUp() public {
        networksJson = new NetworksJson();
    }

    function test_reads_address_json_on_existing_chain_id() public {
        uint256 chainId = 1;
        assertEq(
            networksJson.addressByChainId("GPv2Settlement", chainId),
            address(0x9008D19f58AAbD9eD0D60971565AA8510560ab41)
        );
        vm.chainId(chainId);
        assertEq(networksJson.addressOf("GPv2Settlement"), address(0x9008D19f58AAbD9eD0D60971565AA8510560ab41));
    }

    function test_reverts_reads_address_json_on_unsupported_chain_id() public {
        uint256 chainId = 31333333333333337;
        vm.expectRevert();
        networksJson.addressByChainId("GPv2Settlement", chainId);
        vm.chainId(chainId);
        vm.expectRevert();
        networksJson.addressOf("GPv2Settlement");
    }
}
