// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Harness, Helper} from "./Helper.sol";
import {Eip712} from "test/libraries/Eip712.sol";

contract DomainSeparator is Helper {
    function test_TYPE_HASH_matches_the_EIP_712_order_type_hash() public view {
        bytes32 expectedDomainSeparator = Eip712.hashStruct(
            Eip712.EIP712Domain({
                name: "Gnosis Protocol",
                version: "v2",
                chainId: block.chainid,
                verifyingContract: address(executor)
            })
        );
        assertEq(executor.domainSeparator(), expectedDomainSeparator);
    }

    function test_should_have_a_different_replay_protection_for_each_deployment() public {
        Harness signing = new Harness();
        assertNotEq(executor.domainSeparator(), signing.domainSeparator());
    }
}
