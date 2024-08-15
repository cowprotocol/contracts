// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2Order, GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Sign} from "test/libraries/Sign.sol";
import {GPv2SigningTestInterface} from "test/src/GPv2SigningTestInterface.sol";

// TODO: move the content of `GPv2SigningTestInterface` here once all tests have
// been removed.
// solhint-disable-next-line no-empty-blocks
contract Harness is GPv2SigningTestInterface {
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
