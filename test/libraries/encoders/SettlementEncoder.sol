// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {
    IERC20,
    GPv2Order,
    GPv2Trade,
    GPv2Signing,
    GPv2Interaction,
    GPv2Settlement
} from "src/contracts/GPv2Settlement.sol";

import {Sign} from "../Sign.sol";
import {Trade} from "../Trade.sol";

import {TokenRegistry} from "./TokenRegistry.sol";

library SettlementEncoder {
    using GPv2Order for GPv2Order.Data;
    using Trade for GPv2Order.Data;
    using Sign for Vm;
    using TokenRegistry for TokenRegistry.State;
    using TokenRegistry for address;
    using TokenRegistry for bytes32;

    /// The stage an interaction should be executed in
    enum InteractionStage {
        PRE,
        INTRA,
        POST
    }

    /**
     * Order refund data.
     *
     * @dev after the London hardfork (specifically the introduction of EIP-3529)
     * order refunds have become meaningless as the refunded amount is less than the
     * gas cost of triggering the refund. The logic surrounding this feature is kept
     * in order to keep full test coverage and in case the value of a refund will be
     * increased again in the future. However, order refunds should not be used in
     * an actual settlement.
     */
    struct OrderRefunds {
        bytes[] filledAmounts;
        bytes[] preSignatures;
    }

    /// Encoded settlement parameters
    struct EncodedSettlement {
        IERC20[] tokens;
        uint256[] clearingPrices;
        GPv2Trade.Data[] trades;
        GPv2Interaction.Data[][3] interactions;
    }

    /// State for the settlement encoder (a stateful library)
    struct State {
        bytes32 tokenRegistrySlot;
        GPv2Trade.Data[] trades;
        GPv2Interaction.Data[][3] interactions;
        OrderRefunds refunds;
    }

    bytes32 internal constant STATE_STORAGE_SLOT = keccak256("SettlementEncoder.storage");

    /// @dev Make a new settlement encoder derived from the specified encoder address
    function makeSettlementEncoder(address encoder) internal returns (State storage state) {
        bytes32 slot = keccak256(abi.encodePacked(STATE_STORAGE_SLOT, encoder));
        assembly {
            state.slot := slot
        }

        setTokenRegistry(state, encoder);
    }

    /// @dev Allow an arbitrary token registry to be set
    function setTokenRegistry(State storage state, address registry) internal {
        state.tokenRegistrySlot = registry.makeTokenRegistry().tokenRegistrySlot();
    }

    /// @dev Add a token to the token registry
    function addToken(State storage state, IERC20 token) internal {
        state.tokenRegistrySlot.tokenRegistry().indexOf(token);
    }

    /// @dev Retrieve all the tokens in the token registry
    function tokens(State storage state) internal returns (IERC20[] memory) {
        TokenRegistry.State storage tokenRegistry = state.tokenRegistrySlot.tokenRegistry();
        return tokenRegistry.getTokens();
    }

    /// @dev Automaticatlly append all the order refunds to the POST interactions and return all the interactions
    function interactions(State storage state, address settlement)
        internal
        view
        returns (GPv2Interaction.Data[][3] memory)
    {
        GPv2Interaction.Data[] memory r = encodeOrderRefunds(state, settlement);

        // All the order refunds are encoded in the POST interactions so we take some liberty and
        // use a short variable to represent the POST stage.
        uint256 POST = uint256(InteractionStage.POST);
        GPv2Interaction.Data[] memory postInteractions =
            new GPv2Interaction.Data[](state.interactions[POST].length + r.length);

        for (uint256 i = 0; i < state.interactions[POST].length; i++) {
            postInteractions[i] = state.interactions[POST][i];
        }

        for (uint256 i = 0; i < r.length; i++) {
            postInteractions[state.interactions[POST].length + i] = r[i];
        }

        return [
            state.interactions[uint256(InteractionStage.PRE)],
            state.interactions[uint256(InteractionStage.INTRA)],
            postInteractions
        ];
    }

    /// @dev Add a trade to the state with the given order, signature, and executed amount
    function encodeTrade(
        State storage state,
        GPv2Order.Data memory order,
        Sign.Signature memory signature,
        uint256 executedAmount
    ) internal {
        state.trades.push(order.toTrade(tokens(state), signature, executedAmount));
    }

    /// @dev Sign and encode a trade
    function signEncodeTrade(
        State storage state,
        Vm vm,
        Vm.Wallet memory owner,
        GPv2Order.Data memory order,
        bytes32 domainSeparator,
        GPv2Signing.Scheme signingScheme,
        uint256 executedAmount
    ) internal {
        Sign.Signature memory signature = vm.sign(owner, order, signingScheme, domainSeparator);
        encodeTrade(state, order, signature, executedAmount);
    }

    /// @dev Append an interaction to the state at the specified stage
    function addInteraction(State storage state, GPv2Interaction.Data memory interaction, InteractionStage stage)
        internal
    {
        state.interactions[uint256(stage)].push(interaction);
    }

    /// @dev Append order funds to the state
    function addOrderRefunds(State storage state, OrderRefunds memory orderRefunds) internal {
        if (orderRefunds.filledAmounts.length > 0) {
            for (uint256 i = 0; i < orderRefunds.filledAmounts.length; i++) {
                bytes memory filledAmount = orderRefunds.filledAmounts[i];
                if (filledAmount.length != GPv2Order.UID_LENGTH) {
                    revert("Invalid order UID length");
                }
                state.refunds.filledAmounts.push(filledAmount);
            }
        }

        if (orderRefunds.preSignatures.length > 0) {
            for (uint256 i = 0; i < orderRefunds.preSignatures.length; i++) {
                bytes memory preSignature = orderRefunds.preSignatures[i];
                if (preSignature.length != GPv2Order.UID_LENGTH) {
                    revert("Invalid order UID length");
                }
                state.refunds.preSignatures.push(preSignature);
            }
        }
    }

    /// @dev Encode the current state into a settlement
    function encode(State storage state, GPv2Settlement settlement) internal returns (EncodedSettlement memory) {
        return EncodedSettlement({
            tokens: tokens(state),
            clearingPrices: state.tokenRegistrySlot.tokenRegistry().clearingPrices(),
            trades: state.trades,
            interactions: interactions(state, address(settlement))
        });
    }

    /// @dev Encode just the setup interactions and use an otherwise empty encoded settlement
    function encode(State storage, GPv2Interaction.Data[] memory setupInteractions)
        internal
        pure
        returns (EncodedSettlement memory encodedSettlement)
    {
        encodedSettlement.interactions[uint256(InteractionStage.INTRA)] = setupInteractions;
    }

    /// @dev Encode the order refunds into interactions
    function encodeOrderRefunds(State storage state, address settlement)
        private
        view
        returns (GPv2Interaction.Data[] memory refunds_)
    {
        uint256 numInteractions =
            (state.refunds.filledAmounts.length > 0 ? 1 : 0) + (state.refunds.preSignatures.length > 0 ? 1 : 0);
        refunds_ = new GPv2Interaction.Data[](numInteractions);

        uint256 i = 0;
        if (state.refunds.filledAmounts.length > 0) {
            refunds_[i++] = refundFnEncoder(
                settlement, GPv2Settlement.freeFilledAmountStorage, state.refunds.filledAmounts
            );
        }

        if (state.refunds.preSignatures.length > 0) {
            refunds_[i] = refundFnEncoder(
                settlement, GPv2Settlement.freePreSignatureStorage, state.refunds.preSignatures
            );
        }
    }

    /// @dev Encode a refund function call
    function refundFnEncoder(address settlement, function(bytes[] calldata) fn, bytes[] memory orderUids)
        private
        pure
        returns (GPv2Interaction.Data memory)
    {
        return GPv2Interaction.Data({target: settlement, value: 0, callData: abi.encodeCall(fn, (orderUids))});
    }
}
