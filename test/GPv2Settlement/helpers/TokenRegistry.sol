// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {Base} from "../Helper.sol";

abstract contract TokenRegistry is Base {
    IERC20[] public _tokenRegistryTokens;
    mapping(IERC20 => uint256) public _tokenRegistryIndices;
    mapping(IERC20 => uint256) public prices;

    // equal to address(uint160(uint256(keccak256("TokenRegistry: invalid token placeholder"))
    IERC20 private constant PLACE_HOLDER = IERC20(0x17c380062AB855626A6Ab34f687945Bd3066F7D8);

    error ArrayLengthMismatch();

    modifier requirePlaceholder() {
        if (_tokenRegistryTokens.length == 0) {
            _tokenRegistryTokens.push(PLACE_HOLDER);
        }
        _;
    }

    /// @dev Retrieve the token index for the specified token address. If the token
    /// is not already in the registry, it will be added.
    function indexOf(IERC20 token) internal requirePlaceholder returns (uint256 i) {
        i = _tokenRegistryIndices[token];
        if (i == 0) {
            i = _tokenRegistryTokens.length;
            _tokenRegistryTokens.push(token);
            _tokenRegistryIndices[token] = i;
        }
    }

    /// @dev Set the price for the specified token
    function setPrices(IERC20[] calldata _tokens, uint256[] calldata _prices) internal requirePlaceholder {
        if (_tokens.length != _prices.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = _tokens[i];
            indexOf(token);
            prices[token] = _prices[i];
        }
    }

    /// @dev Gets the array of token addresses in the registry
    function tokens() internal requirePlaceholder returns (IERC20[] memory) {
        // Skip the dummy token
        if (_tokenRegistryTokens.length == 1) {
            return new IERC20[](0);
        }

        IERC20[] memory _tokens = new IERC20[](_tokenRegistryTokens.length - 1);
        for (uint256 i = 1; i < _tokenRegistryTokens.length; i++) {
            _tokens[i - 1] = _tokenRegistryTokens[i];
        }
        return _tokens;
    }

    /// @dev Returns a clearing price vector for the current settlement tokens price mapping
    function clearingPrices() internal requirePlaceholder returns (uint256[] memory) {
        // Skip the dummy token
        if (_tokenRegistryTokens.length == 1) {
            return new uint256[](0);
        }

        uint256[] memory _prices = new uint256[](_tokenRegistryTokens.length - 1);
        for (uint256 i = 1; i < _tokenRegistryTokens.length; i++) {
            _prices[i - 1] = prices[_tokenRegistryTokens[i]];
        }
        return _prices;
    }
}
