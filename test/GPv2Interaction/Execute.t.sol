// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {Helper} from "./Helper.sol";

import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";

contract NonPayable {}

contract Transfer is Helper {
    function test_should_pass_on_successful_execution() public {
        vm.expectCall(address(0), hex"");
        executor.executeTest(GPv2Interaction.Data({target: address(0), callData: hex"", value: 0}));
    }

    function test_revert_when_interaction_reverts() public {
        address reverter = makeAddr("reverting contract");
        bytes memory callData = hex"0badda7a";
        vm.mockCallRevert(reverter, callData, "test error");
        vm.expectRevert("test error");
        executor.executeTest(GPv2Interaction.Data({target: reverter, value: 0, callData: callData}));
    }

    function test_should_send_Ether_when_value_is_specified() public {
        address target = makeAddr("interaction target");
        uint256 value = 42;
        bytes memory callData = "0xca11d47a";

        vm.deal(address(executor), value);

        assertEq(address(executor).balance, value);
        vm.expectCall(target, value, callData);
        executor.executeTest(GPv2Interaction.Data({target: target, value: value, callData: callData}));
        assertEq(address(executor).balance, 0);
    }

    function test_should_send_Ether_to_EOAs() public {
        address target = makeAddr("transfer target");
        uint256 value = 42;

        vm.deal(address(executor), value);

        assertEq(address(executor).balance, value);
        assertEq(target.balance, 0);
        executor.executeTest(GPv2Interaction.Data({target: target, value: value, callData: hex""}));
        assertEq(address(executor).balance, 0);
        assertEq(target.balance, value);
    }

    function test_reverts_when_sending_Ether_to_non_payable_contracts() public {
        NonPayable target = new NonPayable();
        uint256 value = 42;

        vm.deal(address(executor), value);

        vm.expectRevert(bytes(""));
        executor.executeTest(GPv2Interaction.Data({target: address(target), value: value, callData: hex""}));
    }
}
