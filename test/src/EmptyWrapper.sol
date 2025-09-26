// SPDX-License-Identifier: LGPL-3.0-or-later
// solhint-disable-next-line compiler-version
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "src/contracts/GPv2Wrapper.sol";

contract EmptyWrapper is GPv2Wrapper {
    constructor(address payable upstreamSettlement_) GPv2Wrapper(upstreamSettlement_) {}

    function _wrap(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions,
        bytes calldata /*wrappedData*/
    ) internal override {
        _internalSettle(tokens, clearingPrices, trades, interactions);
    }
}
