// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Order.sol";

type Registry is bytes32;

library TokenRegistry {
    struct State {
        IERC20[] tokens;
        mapping(IERC20 => uint256) tokenIndices;
        mapping(IERC20 => uint256) prices;
    }

    bytes32 internal constant STATE_STORAGE_SLOT = keccak256("TokenRegistry.storage");

    /// @dev We want to make sure that the token registry never allocates
    /// the first `tokens` entry to a valid token.  This is because in the
    /// inverse token mapping in storage we can't distinguish the cases
    /// "mapping has no entry" and "mapping has entry zero".
    modifier hydrateArray(State storage state) {
        if (state.tokens.length == 0) {
            state.tokens.push(IERC20(address(uint160(uint256(keccak256("TokenRegistry: invalid token placeholder"))))));
        }
        _;
    }

    /// @dev Allocates a new token registry for the specified registry ID
    function tokenRegistry(Registry id) internal pure returns (State storage state) {
        bytes32 slot = keccak256(abi.encodePacked(STATE_STORAGE_SLOT, id));
        assembly {
            state.slot := slot
        }
    }

    /// @dev Retrieve the token index for the specified token address. If the token
    /// is not already in the registry, it will be added.
    function pushIfNotPresentIndexOf(State storage state, IERC20 token)
        internal
        hydrateArray(state)
        returns (uint256 i)
    {
        i = state.tokenIndices[token];
        if (i == 0) {
            i = state.tokens.length;
            state.tokens.push(token);
            state.tokenIndices[token] = i;
        }
    }

    /// @dev Set the price for the specified tokens
    function setPrices(State storage state, IERC20[] memory _tokens, uint256[] memory _prices)
        internal
        hydrateArray(state)
    {
        if (_tokens.length != _prices.length) {
            revert("Array length mismatch");
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = _tokens[i];
            pushIfNotPresentIndexOf(state, token);
            state.prices[token] = _prices[i];
        }
    }

    /// @dev Set the price for specified token
    function setPrice(State storage state, IERC20 token, uint256 price) internal hydrateArray(state) {
        pushIfNotPresentIndexOf(state, token);
        state.prices[token] = price;
    }

    /// @dev Gets the array of tokens in the registry
    function getTokens(State storage state) internal hydrateArray(state) returns (IERC20[] memory) {
        // Skip the dummy token
        IERC20[] memory tokens_ = new IERC20[](state.tokens.length - 1);
        for (uint256 i = 1; i < state.tokens.length; i++) {
            tokens_[i - 1] = state.tokens[i];
        }
        return tokens_;
    }

    /// @dev Returns a clearing price vector for the current settlement tokens price mapping
    function clearingPrices(State storage state) internal hydrateArray(state) returns (uint256[] memory) {
        // Skip the dummy token
        if (state.tokens.length == 1) {
            return new uint256[](0);
        }

        uint256[] memory prices = new uint256[](state.tokens.length - 1);
        for (uint256 i = 1; i < state.tokens.length; i++) {
            prices[i - 1] = state.prices[state.tokens[i]];
        }
        return prices;
    }

    /// @dev Returns the token indices for the specified order
    function tokenIndices(State storage state, GPv2Order.Data memory order)
        internal
        hydrateArray(state)
        returns (uint256, uint256)
    {
        uint256 sellTokenIndex = pushIfNotPresentIndexOf(state, order.sellToken);
        uint256 buyTokenIndex = pushIfNotPresentIndexOf(state, order.buyToken);
        return (sellTokenIndex - 1, buyTokenIndex - 1);
    }

    /// @dev Returns the token index for the specified token
    function tokenIndex(State storage state, IERC20 token) internal hydrateArray(state) returns (uint256) {
        uint256 index = pushIfNotPresentIndexOf(state, token);
        return index - 1;
    }
}
