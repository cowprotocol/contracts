// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {Helper} from "./Helper.sol";

import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";

interface SomeInterface {
    function someFunctionWithParams(uint256) external;
    function someFunctionWithoutParams() external;
}

contract Transfer is Helper {
    function test_masks_the_function_selector_to_the_first_4_bytes_for_the_emitted_event() public view {
        bytes memory callData = abi.encodeCall(SomeInterface.someFunctionWithParams, (type(uint256).max));
        assertEq(
            executor.selectorTest(GPv2Interaction.Data({target: address(0), callData: callData, value: 0})),
            SomeInterface.someFunctionWithParams.selector
        );
    }

    function test_computes_selector_for_parameterless_functions() public view {
        bytes memory callData = abi.encodeCall(SomeInterface.someFunctionWithoutParams, ());
        assertEq(
            executor.selectorTest(GPv2Interaction.Data({target: address(0), callData: callData, value: 0})),
            SomeInterface.someFunctionWithoutParams.selector
        );
    }

    function test_uses_0_selector_for_empty_or_short_calldata() public view {
        GPv2Interaction.Data memory interaction = GPv2Interaction.Data({target: address(0), callData: hex"", value: 0});
        assertEq(executor.selectorTest(interaction), bytes4(0));
        interaction.callData = hex"abcdef";
        assertEq(executor.selectorTest(interaction), bytes4(0));
    }
}
