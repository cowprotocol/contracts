// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Sign} from "test/libraries/Sign.sol";

contract Harness is GPv2Signing {
    function recoverOrderFromTradeTest(IERC20[] calldata tokens, GPv2Trade.Data calldata trade)
        external
        view
        returns (GPv2Signing.RecoveredOrder memory recoveredOrder)
    {
        recoveredOrder = allocateRecoveredOrder();
        recoverOrderFromTrade(recoveredOrder, tokens, trade);
    }

    function recoverOrderSignerTest(GPv2Order.Data memory order, Sign.Signature calldata signature)
        public
        view
        returns (address owner)
    {
        (, owner) = recoverOrderSigner(order, signature.scheme, signature.data);
    }
}

contract Helper is Test {
    Harness internal executor;
    bytes32 internal domainSeparator;

    function setUp() public {
        executor = new Harness();
        domainSeparator = executor.domainSeparator();
    }
}
