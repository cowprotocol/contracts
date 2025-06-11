// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {GPv2Order, GPv2Signing, GPv2Trade, IERC20, IVault} from "src/contracts/GPv2Settlement.sol";

import {Sign} from "../Sign.sol";
import {Trade} from "../Trade.sol";
import {Registry, TokenRegistry} from "./TokenRegistry.sol";

library SwapEncoder {
    using Trade for GPv2Order.Data;
    using Sign for Vm;
    using TokenRegistry for TokenRegistry.State;
    using TokenRegistry for Registry;

    struct Swap {
        bytes32 poolId;
        IERC20 assetIn;
        IERC20 assetOut;
        uint256 amount;
        bytes userData;
    }

    struct EncodedSwap {
        IVault.BatchSwapStep[] swaps;
        IERC20[] tokens;
        GPv2Trade.Data trade;
    }

    struct State {
        Registry tokenRegistry;
        IVault.BatchSwapStep[] steps;
        GPv2Trade.Data trade;
    }

    bytes32 internal constant STATE_STORAGE_SLOT = keccak256("SwapEncoder.storage");

    /// @dev Make a new swap encoder, bumping the nonce
    function makeSwapEncoder() internal returns (State storage state) {
        uint256 nonce;
        bytes32 nonceSlot = STATE_STORAGE_SLOT;
        assembly {
            nonce := sload(nonceSlot)
            sstore(nonceSlot, add(nonce, 1))
        }
        bytes32 slot = keccak256(abi.encodePacked(STATE_STORAGE_SLOT, nonce));
        assembly {
            state.slot := slot
        }

        setTokenRegistry(state, Registry.wrap(keccak256(abi.encode(slot))));
    }

    /// @dev Allow to set a custom token registry
    function setTokenRegistry(State storage state, Registry registry) internal {
        state.tokenRegistry = registry;
    }

    /// @dev Retrieve all the tokens in the token registry
    function tokens(State storage state) internal returns (IERC20[] memory) {
        TokenRegistry.State storage tokenRegistry = state.tokenRegistry.tokenRegistry();
        return tokenRegistry.getTokens();
    }

    /// @dev Add a token to the token registry
    function addToken(State storage state, IERC20 token) internal {
        state.tokenRegistry.tokenRegistry().pushIfNotPresentIndexOf(token);
    }

    /// @dev Encode a swap step
    function encodeSwapStep(State storage state, Swap memory swap) internal {
        state.steps.push(toSwapStep(state, swap));
    }

    /// @dev Given an order, signature and limitAmount, encode a trade
    function encodeTrade(
        State storage state,
        GPv2Order.Data memory order,
        Sign.Signature memory signature,
        uint256 limitAmount
    ) internal {
        if (limitAmount == 0) {
            limitAmount = order.kind == GPv2Order.KIND_SELL ? order.buyAmount : order.sellAmount;
        }
        (uint256 sellTokenIndex, uint256 buyTokenIndex) =
            TokenRegistry.tokenIndices(state.tokenRegistry.tokenRegistry(), order);
        GPv2Trade.Data memory trade_ = order.toTrade(sellTokenIndex, buyTokenIndex, signature, limitAmount);

        state.trade.sellTokenIndex = trade_.sellTokenIndex;
        state.trade.buyTokenIndex = trade_.buyTokenIndex;
        state.trade.receiver = trade_.receiver;
        state.trade.sellAmount = trade_.sellAmount;
        state.trade.buyAmount = trade_.buyAmount;
        state.trade.validTo = trade_.validTo;
        state.trade.appData = trade_.appData;
        state.trade.feeAmount = trade_.feeAmount;
        state.trade.flags = trade_.flags;
        state.trade.executedAmount = trade_.executedAmount;
        state.trade.signature = trade_.signature;
    }

    /// @dev Given an order and a wallet, sign and encode a trade
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

    /// @dev Encode the state into an EncodedSwap struct
    function encode(State storage state) internal returns (EncodedSwap memory) {
        return EncodedSwap(state.steps, tokens(state), state.trade);
    }

    /// @dev Convert a Swap struct into a BatchSwapStep struct
    function toSwapStep(State storage state, Swap memory swap) private returns (IVault.BatchSwapStep memory step) {
        TokenRegistry.State storage tokenRegistry = state.tokenRegistry.tokenRegistry();
        step.poolId = swap.poolId;
        step.assetInIndex = tokenRegistry.pushIfNotPresentIndexOf(swap.assetIn);
        step.assetOutIndex = tokenRegistry.pushIfNotPresentIndexOf(swap.assetOut);
        step.amount = swap.amount;
        step.userData = swap.userData;
    }
}
