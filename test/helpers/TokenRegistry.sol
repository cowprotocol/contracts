// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

contract TokenRegistry {
    IERC20[] public tokens;
    mapping(IERC20 => uint256) public tokenIndices;
    mapping(IERC20 => uint256) public prices;

    error ArrayLengthMismatch();

    constructor() {
        /// @dev Add a dummy token to make the array 1-indexed
        tokens.push(IERC20(address(0)));
    }

    /// @dev Retrieve the token index for the specified token address. If the token
    /// is not already in the registry, it will be added.
    function index(IERC20 token) public returns (uint256 i) {
        i = tokenIndices[token];
        if (i == 0) {
            i = tokens.length;
            tokens.push(token);
            tokenIndices[token] = i;
        }
    }

    /// @dev Set the price for the specified token
    function setPrices(IERC20[] calldata _tokens, uint256[] calldata _prices) public {
        if (_tokens.length != _prices.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = _tokens[i];
            index(token);
            prices[token] = _prices[i];
        }
    }

    /// @dev Gets the array of token addresses in the registry
    function addresses() public view returns (IERC20[] memory) {
        IERC20[] memory _tokens = new IERC20[](tokens.length - 1);
        for (uint256 i = 1; i < tokens.length; i++) {
            _tokens[i - 1] = tokens[i];
        }
        return _tokens;
    }

    /// @dev Returns a clearing price vector for the current settlement tokens price mapping
    function clearingPrices() public view returns (uint256[] memory) {
        uint256[] memory _prices = new uint256[](tokens.length - 1);
        for (uint256 i = 1; i < tokens.length; i++) {
            _prices[i - 1] = prices[tokens[i]];
        }
        return _prices;
    }
}
