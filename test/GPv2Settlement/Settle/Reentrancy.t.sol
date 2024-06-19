// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20, GPv2Order, GPv2Interaction, GPv2Settlement} from "src/contracts/GPv2Settlement.sol";

import {Harness, Helper} from "../Helper.sol";

import {Settlement} from "test/libraries/Settlement.sol";
import {Sign} from "test/libraries/Sign.sol";
import {Trade} from "test/libraries/Trade.sol";
import {Order} from "test/libraries/Order.sol";

import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

// solhint-disable func-name-mixedcase
contract Reentrancy is Helper {
    using Settlement for Harness;
    using Trade for GPv2Order.Data;
    using SettlementEncoder for SettlementEncoder.State;
    using SwapEncoder for SwapEncoder.State;

    function test_revert_rejects_reentrancy_attempts_via_interactions() public {
        reject_reentrancy_attempts_via_interactions(owner, settle_reentrancy_calldata());
        reject_reentrancy_attempts_via_interactions(owner, swap_reentrancy_calldata());
    }

    function test_revert_rejects_reentrancy_attempts_even_as_a_registered_solver() public {
        reject_reentrancy_attempts_via_interactions(address(settlement), settle_reentrancy_calldata());
        reject_reentrancy_attempts_via_interactions(address(settlement), swap_reentrancy_calldata());
    }

    function reject_reentrancy_attempts_via_interactions(address who, bytes memory data) internal {
        vm.prank(owner);
        allowList.addSolver(who);

        GPv2Interaction.Data[] memory interactions = new GPv2Interaction.Data[](1);
        interactions[0] = GPv2Interaction.Data({target: address(settlement), value: 0, callData: data});

        vm.prank(who);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        settlement.settle(encoder.encode(interactions));
    }

    function settle_reentrancy_calldata() internal returns (bytes memory) {
        SettlementEncoder.EncodedSettlement memory empty;
        return abi.encodeWithSelector(
            GPv2Settlement.settle.selector, empty.tokens, empty.clearingPrices, empty.trades, empty.interactions
        );
    }

    function swap_reentrancy_calldata() internal returns (bytes memory) {
        swapEncoder.addToken(IERC20(address(0)));
        swapEncoder.encodeTrade(Order.emptySell(), Sign.emptyEIP712(), 0);
        SwapEncoder.EncodedSwap memory malicious = swapEncoder.encode();

        return abi.encodeWithSelector(GPv2Settlement.swap.selector, malicious.swaps, malicious.tokens, malicious.trade);
    }
}
