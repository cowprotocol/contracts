// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";

import {Base, Helper} from "../Helper.sol";

import {GPv2Settlement, Settlement, GPv2Order, Sign, Trade} from "../helpers/Settlement.sol";
import {Encoder} from "../helpers/Encoder.sol";
import {Swap} from "../helpers/Swap.sol";

// solhint-disable func-name-mixedcase
contract Settle is Helper, Settlement, Swap {
    using Trade for GPv2Order.Data;

    function setUp() public override(Base, Helper) {
        super.setUp();
    }

    function test_settle_revert_on_reentrancy_from_solver() public {
        address solver = makeAddr("solver");
        address owner = makeAddr("owner");
        Settlement emptyEncoder = new Settlement();
        emptyEncoder.setDomainSeparator(domainSeparator);

        vm.prank(owner);
        allowList.addSolver(solver);

        EncodedSettlement memory malicious = emptyEncoder.encode();
        GPv2Interaction.Data memory interaction = GPv2Interaction.Data({
            target: address(settlement),
            value: 0,
            callData: abi.encodeCall(
                GPv2Settlement.settle,
                (malicious.tokens, malicious.clearingPrices, malicious.trades, malicious.interactions)
            )
        });
        vm.prank(solver);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        settle(encode([interaction]));
    }

    /// @dev This override is required to resolve the ambiguity between the `Encoder` and `Swap` contracts.
    function encodeTrade(GPv2Order.Data memory order, Sign.Signature memory signature, uint256 executedAmount)
        public
        virtual
        override(Encoder, Swap)
    {
        Encoder.encodeTrade(order, signature, executedAmount);
    }
}
