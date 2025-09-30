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

import { IERC20 } from "./IERC20.sol";
import { IGPv2Settlement } from  "./IGPv2Settlement.sol";
import { GPv2Authentication } from "./GPv2Authentication.sol";
import { GPv2Trade } from "../libraries/GPv2Trade.sol";
import { GPv2Interaction } from "../libraries/GPv2Interaction.sol";

/**
 * @dev Interface for wrappers of the GPv2Settlement contract for CoW orders. It serves as a way for the functionality
 * of the settlement contract to be expanded without needing to affect the underlying security.
 * A wrapper should:
 * * call the equivalent `settle` on the GPv2Settlement contract (0x9008D19f58AAbD9eD0D60971565AA8510560ab41)
 * * verify that the caller is authorized via the GPv2Authentication contract registered on the settlement contract.
 * A wrapper may also execute, or otherwise put the blockchain in a state that needs to be established prior or after settlement.
 * Prior to usage, the wrapper itself needs to be approved by the GPv2Authentication contract.
 */
interface IGPv2Wrapper {
    function UPSTREAM_SETTLEMENT() external view returns (IGPv2Settlement);
    function AUTHENTICATOR() external view returns (GPv2Authentication);

    /**
     * @dev Called to initiate a wrapped call against the settlement function. Most of the arguments are shared with GPv2Settlement.settle().
     * @param wrapperData any additional data which is needed for the wrapper to complete its task.
     */
    function wrappedSettle(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions,
        bytes calldata wrapperData
    ) external;
}
