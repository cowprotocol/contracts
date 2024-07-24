// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

// solhint-disable func-name-mixedcase
contract Harness is GPv2Signing {
    constructor(bytes32 _domainSeparator) {
        domainSeparator = _domainSeparator;
    }

    function exposed_recoverOrderFromTrade(
        RecoveredOrder memory recoveredOrder,
        IERC20[] calldata tokens,
        GPv2Trade.Data calldata trade
    ) external view {
        recoverOrderFromTrade(recoveredOrder, tokens, trade);
    }

    function exposed_recoverOrderSigner(GPv2Order.Data memory order, Scheme signingScheme, bytes calldata signature)
        external
        view
        returns (bytes32 orderDigest, address owner)
    {
        (orderDigest, owner) = recoverOrderSigner(order, signingScheme, signature);
    }
}
