// SPDX-License-Identifier: LGPL-3.0-or-later
// solhint-disable-next-line compiler-version
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "src/contracts/libraries/GPv2Order.sol";
import "src/contracts/libraries/GPv2Trade.sol";
import "src/contracts/mixins/GPv2Signing.sol";

contract GPv2SigningTestInterface is GPv2Signing {
    function recoverOrderFromTradeTest(IERC20[] calldata tokens, GPv2Trade.Data calldata trade)
        external
        view
        returns (RecoveredOrder memory recoveredOrder)
    {
        recoveredOrder = allocateRecoveredOrder();
        recoverOrderFromTrade(recoveredOrder, tokens, trade);
    }

    function recoverOrderSignerTest(
        GPv2Order.Data memory order,
        GPv2Signing.Scheme signingScheme,
        bytes calldata signature
    ) external view returns (address owner) {
        (, owner) = recoverOrderSigner(order, signingScheme, signature);
    }
}
