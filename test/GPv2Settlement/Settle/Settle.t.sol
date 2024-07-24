// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Helper} from "../Helper.sol";

import {GPv2Interaction, GPv2Settlement} from "src/contracts/GPv2Settlement.sol";

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

    function test_executes_interaction_stages_in_the_correct_order() public {
        CallOrderEnforcer callOrderEnforcer = new CallOrderEnforcer();
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(callOrderEnforcer),
                value: 0,
                callData: abi.encodeCall(CallOrderEnforcer.post, ())
            }),
            SettlementEncoder.InteractionStage.POST
        );
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(callOrderEnforcer),
                value: 0,
                callData: abi.encodeCall(CallOrderEnforcer.pre, ())
            }),
            SettlementEncoder.InteractionStage.PRE
        );
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(callOrderEnforcer),
                value: 0,
                callData: abi.encodeCall(CallOrderEnforcer.intra, ())
            }),
            SettlementEncoder.InteractionStage.INTRA
        );

        vm.prank(solver);
        settle(encoder.encode(settlement));
        assertEq(uint256(callOrderEnforcer.lastCall()), uint256(CallOrderEnforcer.Called.Post));
    }
}

/// Contract that exposes three functions that must be called in the expected
/// order. The last called function is stored in the state as `lastCall`.
contract CallOrderEnforcer {
    enum Called {
        None,
        Pre,
        Intra,
        Post
    }

    Called public lastCall = Called.None;

    function pre() public {
        require(lastCall == Called.None, "called `pre` but there should have been no other calls before");
        lastCall = Called.Pre;
    }

    function intra() public {
        require(lastCall == Called.Pre, "called `intra` but previous call wasn't `pre`");
        lastCall = Called.Intra;
    }

    function post() public {
        require(lastCall == Called.Intra, "called `post` but previous call wasn't `intra`");
        lastCall = Called.Post;
    }
}
