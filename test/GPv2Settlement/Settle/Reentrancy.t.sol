// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2Interaction, GPv2Order, GPv2Settlement, IERC20} from "src/contracts/GPv2Settlement.sol";

import {Helper} from "../Helper.sol";

import {Order} from "test/libraries/Order.sol";
import {GPv2Signing, Sign} from "test/libraries/Sign.sol";
import {Trade} from "test/libraries/Trade.sol";

import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";
import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";

contract Reentrancy is Helper {
    using Trade for GPv2Order.Data;
    using SettlementEncoder for SettlementEncoder.State;
    using SwapEncoder for SwapEncoder.State;

    function test_settle_rejects_reentrancy_attempts_via_interactions() public {
        rejectReentrancyAttemptsViaInteractions(settleReentrancyCalldata(), false);
    }

    function test_settle_rejects_reentrancy_attempts_via_interactions_as_a_registered_solver() public {
        rejectReentrancyAttemptsViaInteractions(settleReentrancyCalldata(), true);
    }

    function test_swap_rejects_reentrancy_attempts_via_interactions() public {
        rejectReentrancyAttemptsViaInteractions(swapReentrancyCalldata(), false);
    }

    function test_swap_rejects_reentrancy_attempts_via_interactions_as_a_registered_solver() public {
        rejectReentrancyAttemptsViaInteractions(swapReentrancyCalldata(), true);
    }

    function rejectReentrancyAttemptsViaInteractions(bytes memory data, bool settlementContractIsSolver) internal {
        if (settlementContractIsSolver) {
            vm.prank(owner);
            allowList.addSolver(address(settlement));
        }

        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](1);
        interactions[0] = GPv2Interaction.Data({target: address(settlement), value: 0, callData: data});

        vm.prank(solver);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        settle(encoder.encode(interactions));
    }

    function settleReentrancyCalldata() internal pure returns (bytes memory) {
        SettlementEncoder.EncodedSettlement memory empty;
        return
            abi.encodeCall(
                GPv2Settlement.settle, (empty.tokens, empty.clearingPrices, empty.trades, empty.interactions)
            );
    }

    function swapReentrancyCalldata() internal returns (bytes memory) {
        swapEncoder.addToken(IERC20(address(0)));
        Sign.Signature memory empty = Sign.Signature({scheme: GPv2Signing.Scheme.Eip712, data: new bytes(65)});

        swapEncoder.encodeTrade(Order.emptySell(), empty, 0);
        SwapEncoder.EncodedSwap memory malicious = swapEncoder.encode();

        return abi.encodeCall(GPv2Settlement.swap, (malicious.swaps, malicious.tokens, malicious.trade));
    }
}
