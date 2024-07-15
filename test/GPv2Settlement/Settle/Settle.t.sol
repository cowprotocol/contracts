// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Harness, Helper} from "../Helper.sol";

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
        settlement.settle(encoder.encode(settlement));
    }

    function test_executes_interactions_stages_in_the_correct_order() public {
        // Set the expected event emitted
        vm.expectEmit(address(settlement));
        add_indexed_interaction_helper(encoder, SettlementEncoder.InteractionStage.PRE);
        add_indexed_interaction_helper(encoder, SettlementEncoder.InteractionStage.INTRA);
        add_indexed_interaction_helper(encoder, SettlementEncoder.InteractionStage.POST);
        emit GPv2Settlement.Settlement(solver);

        // Now, start recording logs to prevent recording extraneous logs
        vm.recordLogs();
        vm.prank(solver);
        settlement.settle(encoder.encode(settlement));

        // Assert that the correct number of logs were recorded
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);
        assertEq(entries[0].data, abi.encodePacked(bytes32(bytes20(address(0))), bytes32(bytes8(uint8(SettlementEncoder.InteractionStage.PRE)))));
        assertEq(entries[1].data, abi.encodePacked(bytes32(bytes20(address(0))), bytes32(bytes8(uint8(SettlementEncoder.InteractionStage.INTRA)))));
        assertEq(entries[2].data, abi.encodePacked(bytes32(bytes20(address(0))), bytes32(bytes8(uint8(SettlementEncoder.InteractionStage.POST)))));
    }

    function add_indexed_interaction_helper(
        SettlementEncoder.State storage encoder,
        SettlementEncoder.InteractionStage stage
    ) internal {
        encoder.addInteraction(
            GPv2Interaction.Data({target: address(0), value: 0, callData: abi.encode(bytes4(uint32(stage)))}), stage
        );
        emit GPv2Settlement.Interaction(address(0), 0, bytes4(uint32(stage)));
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
