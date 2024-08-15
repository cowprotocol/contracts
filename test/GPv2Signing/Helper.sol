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

    function uint8ToScheme(uint8 scheme) public pure returns (uint8) {
        // Round trip encodes and decodes a uint8 to a Scheme and back. This is
        // useful to make sure the code can't use an internally invalid signing
        // scheme in its internal operations.
        return uint8(GPv2Signing.Scheme(scheme));
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
