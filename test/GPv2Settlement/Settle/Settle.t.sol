// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Helper} from "../Helper.sol";

import {GPv2Interaction, GPv2Order, GPv2Settlement, GPv2Signing, IERC20} from "src/contracts/GPv2Settlement.sol";

import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "test/libraries/encoders/TokenRegistry.sol";

// solhint-disable func-name-mixedcase
contract Settle is Helper {
    using SettlementEncoder for SettlementEncoder.State;
    using TokenRegistry for TokenRegistry.State;
    using TokenRegistry for Registry;

    function test_allowlist_rejects_transactions_from_non_solvers() public {
        vm.expectRevert("GPv2: not a solver");
        settle(emptySettlement());
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

    function test_transfers_sell_tokens_from_owner_and_buy_tokens_to_receiver() public {
        IERC20 sellToken = IERC20(address(deployMockERC20("sell token", "SELL", 18)));
        IERC20 buyToken = IERC20(address(deployMockERC20("buy token", "BUY", 18)));
        address receiver = makeAddr("GPv2Settlement.Settle: receiver");

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: receiver,
            sellAmount: 10 ether,
            buyAmount: 14 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 0);
        // Executed buy amount: 10 sell tokens * 3 / 2 = 15 buy tokens.
        encoder.tokenRegistry.tokenRegistry().setPrice(sellToken, 3);
        encoder.tokenRegistry.tokenRegistry().setPrice(buyToken, 2);

        deal(address(sellToken), trader.addr, 11 ether);
        deal(address(buyToken), address(settlement), 15 ether);
        address vaultRelayer = address(settlement.vaultRelayer());
        vm.prank(trader.addr);
        sellToken.approve(vaultRelayer, 11 ether);

        vm.prank(solver);
        settle(encoder.encode(settlement));

        assertEq(sellToken.balanceOf(trader.addr), 0);
        assertEq(sellToken.balanceOf(address(settlement)), 11 ether);
        assertEq(buyToken.balanceOf(address(settlement)), 0);
        assertEq(buyToken.balanceOf(receiver), 15 ether);
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
