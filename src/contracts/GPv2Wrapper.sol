// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "./interfaces/IGPv2Wrapper.sol";

/**
 * @title A minimalist base that can be extended to safely implement a wrapper. It ensures the most important basic functions of a wrapper are fulfilled
 */
abstract contract GPv2Wrapper is IGPv2Wrapper {
    IGPv2Settlement public immutable UPSTREAM_SETTLEMENT;
    GPv2Authentication public immutable AUTHENTICATOR;

    constructor(address payable upstreamSettlement_) {
        UPSTREAM_SETTLEMENT = IGPv2Settlement(upstreamSettlement_);

        // retrieve the authentication we are supposed to use from the settlement contract
        AUTHENTICATOR = IGPv2Settlement(upstreamSettlement_).authenticator();
    }

    /**
     * @inheritdoc IGPv2Wrapper
     */
    function wrappedSettle(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions,
        bytes calldata wrapperData
    ) external {
        // Revert if not a valid solver
        if (!AUTHENTICATOR.isSolver(msg.sender)) {
            revert("GPv2Wrapper: not a solver");
        }

        _wrap(tokens, clearingPrices, trades, interactions, wrapperData);
    }

    /**
     * @dev The logic for the wrapper. During this function, `_internalSettle` should be called
     */
    function _wrap(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions,
        bytes calldata wrapperData
    ) internal virtual;

    /**
     * @dev Should be called from within (or otherwise as a result of) _wrap. Calls GPv2Settlement.settle().
     */
    function _internalSettle(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions
    ) internal {
        UPSTREAM_SETTLEMENT.settle(tokens, clearingPrices, trades, interactions);
    }
}
