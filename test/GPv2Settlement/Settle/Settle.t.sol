// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Helper} from "../Helper.sol";

import {GPv2Settlement, GPv2Interaction} from "src/contracts/GPv2Settlement.sol";

import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

// solhint-disable func-name-mixedcase
contract Settle is Helper {
    using SettlementEncoder for SettlementEncoder.State;

    function test_allowlist_rejects_transactions_from_non_solvers() public {
        vm.expectRevert("GPv2: not a solver");
        settle(encoder.encode(settlement));
    }

    function test_allowlist_accepts_transactions_from_solvers() public {
        vm.prank(solver);
        settle(encoder.encode(settlement));
    }

    function test_emits_a_settlement_event() public {
        vm.expectEmit(address(settlement));
        emit GPv2Settlement.Settlement(solver);
        vm.prank(solver);
        settle(encoder.encode(settlement));
    }

    function test_reverts_if_encoded_interactions_has_incorrect_number_of_stages() public {
        for (uint256 i = 1; i < 3; i++) {
            GPv2Interaction.Data[][] memory interactions = new GPv2Interaction.Data[][](i * 2);
            assertTrue(interactions.length != 3, "incorrect interaction array length test setup");
            vm.expectRevert();
            // test requires malformed interactions array, therefore use encodeWithSelector
            (bool revertsAsExpected,) = address(settlement).call(
                abi.encodeWithSelector(
                    GPv2Settlement.settle.selector, new bytes32[](0), new uint256[](0), new bytes[](0), interactions
                )
            );
            assertTrue(revertsAsExpected, "incorrect interaction array length did not revert");
        }
    }
}
