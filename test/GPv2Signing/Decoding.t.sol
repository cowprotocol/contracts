// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {EIP1271Verifier, GPv2EIP1271, GPv2Order, GPv2Signing, IERC20} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";
import {Order} from "test/libraries/Order.sol";
import {Sign} from "test/libraries/Sign.sol";

/// @dev Port of the signer-related cases of the TypeScript `decoding` tests
/// (formerly `test/decoding.test.ts`) to Foundry, as part of the test
/// migration tracked in issue #126. The TypeScript tests asserted that
/// `decodeSignatureOwner` returns the expected owner for every signing
/// scheme; these tests assert the same against the on-chain
/// `GPv2Signing.recoverOrderSigner`. Unlike the off-chain decoder, the
/// on-chain recovery also verifies EIP-1271 and pre-sign signatures, so
/// those cases set up the required verification state.
contract Decoding is Helper {
    using GPv2Order for GPv2Order.Data;

    Vm.Wallet private trader;

    constructor() {
        trader = vm.createWallet("GPv2Signing.Decoding trader");
    }

    /// @dev The sample order from the TypeScript tests: the token and
    /// receiver addresses are `fillBytes(20, 0x01)`, `fillBytes(20, 0x02)`
    /// and `fillBytes(20, 0x03)` respectively.
    function sampleOrder() private pure returns (GPv2Order.Data memory) {
        return GPv2Order.Data({
            sellToken: IERC20(0x0101010101010101010101010101010101010101),
            buyToken: IERC20(0x0202020202020202020202020202020202020202),
            receiver: 0x0303030303030303030303030303030303030303,
            sellAmount: 42 ether,
            buyAmount: 13.37 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    /// @dev The address used by the TypeScript tests for the EIP-1271
    /// verifier and the pre-sign signer: `fillDistinctBytes(20, 1)`, that is,
    /// the bytes 1 to 20.
    function sampleAddress() private pure returns (address) {
        return 0x0102030405060708090a0B0c0d0e0f1011121314;
    }

    function test_should_recover_the_signer_of_an_eip712_signature() public {
        GPv2Order.Data memory order = sampleOrder();
        Sign.Signature memory signature = Sign.sign(vm, trader, order, GPv2Signing.Scheme.Eip712, domainSeparator);
        assertEq(executor.recoverOrderSignerTest(order, signature), trader.addr);
    }

    function test_should_recover_the_signer_of_an_ethsign_signature() public {
        GPv2Order.Data memory order = sampleOrder();
        Sign.Signature memory signature = Sign.sign(vm, trader, order, GPv2Signing.Scheme.EthSign, domainSeparator);
        assertEq(executor.recoverOrderSignerTest(order, signature), trader.addr);
    }

    function test_should_recover_the_verifier_of_an_eip1271_signature() public {
        GPv2Order.Data memory order = sampleOrder();
        bytes32 hash = order.hash(domainSeparator);

        address verifier = sampleAddress();
        bytes memory signatureData = hex"1337";
        vm.mockCallRevert(verifier, hex"", "unexpected call to mock contract");
        vm.mockCall(
            verifier,
            abi.encodeCall(EIP1271Verifier.isValidSignature, (hash, signatureData)),
            abi.encode(GPv2EIP1271.MAGICVALUE)
        );

        address owner = executor.recoverOrderSignerTest(order, Sign.sign(EIP1271Verifier(verifier), signatureData));
        assertEq(owner, verifier);
    }

    function test_should_recover_the_signer_of_a_presigned_order() public {
        GPv2Order.Data memory order = sampleOrder();
        address signer = sampleAddress();

        bytes memory orderUid = Order.computeOrderUid(order, domainSeparator, signer);
        vm.prank(signer);
        executor.setPreSignature(orderUid, true);

        address owner = executor.recoverOrderSignerTest(order, Sign.preSign(signer));
        assertEq(owner, signer);
    }
}
