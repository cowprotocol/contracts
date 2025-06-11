// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {GPv2Interaction, GPv2Settlement, Helper} from "./Helper.sol";

contract ExecuteInteractions is Helper {
    function test_executes_valid_interactions() public {
        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](3);
        interactions[0] = GPv2Interaction.Data({
            target: address(new EventEmitter()),
            value: 0.42 ether,
            callData: abi.encodeCall(EventEmitter.emitEvent, (1))
        });
        interactions[1] = GPv2Interaction.Data({
            target: address(new EventEmitter()),
            value: 0.1337 ether,
            callData: abi.encodeCall(EventEmitter.emitEvent, (2))
        });
        interactions[2] = GPv2Interaction.Data({
            target: address(new EventEmitter()),
            value: 0,
            callData: abi.encodeCall(EventEmitter.emitEvent, (3))
        });

        deal(address(settlement), 1 ether);
        for (uint256 i = 0; i < 3; i++) {
            vm.expectEmit(interactions[i].target);
            emit EventEmitter.Event(interactions[i].value, i + 1);
            vm.expectEmit(address(settlement));
            emit GPv2Settlement.Interaction(
                interactions[i].target, interactions[i].value, EventEmitter.emitEvent.selector
            );
        }
        vm.recordLogs();
        settlement.executeInteractionsTest(interactions);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 6, "incorrect number of logs");
    }

    function test_reverts_if_any_interaction_reverts() public {
        address alwaysPasses = makeAddr("ExecuteInteractions: alwaysPasses");
        address alwaysReverts = makeAddr("ExecuteInteractions: alwaysReverts");
        vm.mockCall(alwaysPasses, abi.encodeCall(InteractionHelper.alwaysPasses, ()), hex"");
        vm.mockCallRevert(alwaysReverts, abi.encodeCall(InteractionHelper.alwaysReverts, ()), "mock revert");

        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](2);
        interactions[0] = GPv2Interaction.Data({
            target: alwaysPasses,
            value: 0,
            callData: abi.encodeCall(InteractionHelper.alwaysPasses, ())
        });
        interactions[0] = GPv2Interaction.Data({
            target: alwaysReverts,
            value: 0,
            callData: abi.encodeCall(InteractionHelper.alwaysReverts, ())
        });

        vm.expectRevert("mock revert");
        settlement.executeInteractionsTest(interactions);
    }

    function test_reverts_when_target_is_vaultRelayer() public {
        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](1);
        interactions[0] = GPv2Interaction.Data({target: address(settlement.vaultRelayer()), value: 0, callData: hex""});

        vm.expectRevert("GPv2: forbidden interaction");
        settlement.executeInteractionsTest(interactions);
    }

    function test_reverts_if_settlement_contract_does_not_have_sufficient_Ether() public {
        uint256 value = 1_000_000 ether;
        assertGt(value, address(settlement).balance, "incorrect test setup");

        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](1);
        interactions[0] = GPv2Interaction.Data({target: address(0), value: value, callData: hex""});

        vm.expectRevert();
        settlement.executeInteractionsTest(interactions);
    }

    function test_emits_an_interaction_event() public {
        address target = makeAddr("ExecuteInteractions: target");
        bytes32 parameter = keccak256("some parameter");
        uint256 value = 1 ether;
        vm.mockCall(target, abi.encodeCall(InteractionHelper.someFunction, (parameter)), hex"");

        deal(address(settlement), value);
        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](1);
        interactions[0] = GPv2Interaction.Data({
            target: target,
            value: value,
            callData: abi.encodeCall(InteractionHelper.someFunction, (parameter))
        });
        vm.expectEmit(address(settlement));
        emit GPv2Settlement.Interaction(target, value, InteractionHelper.someFunction.selector);
        settlement.executeInteractionsTest(interactions);
    }
}

contract EventEmitter {
    event Event(uint256 value, uint256 number);

    function emitEvent(uint256 number) external payable {
        emit Event(msg.value, number);
    }
}

interface InteractionHelper {
    function alwaysPasses() external;

    function alwaysReverts() external;

    function someFunction(bytes32 parameter) external;
}
