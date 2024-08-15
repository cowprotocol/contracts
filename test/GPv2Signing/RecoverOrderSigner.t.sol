// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {EIP1271Verifier, GPv2EIP1271, GPv2Order, GPv2Signing, IERC20} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";
import {Order} from "test/libraries/Order.sol";
import {Sign} from "test/libraries/Sign.sol";

contract RecoverOrderSigner is Helper {
    using GPv2Order for GPv2Order.Data;

    Vm.Wallet private trader;

    constructor() {
        trader = vm.createWallet("GPv2Signing.RecoverOrderFromTrade: trader");
    }

    function defaultOrder() internal returns (GPv2Order.Data memory) {
        return GPv2Order.Data({
            sellToken: IERC20(makeAddr("GPv2Sign.RecoverOrderSigner: default order sell token")),
            buyToken: IERC20(makeAddr("GPv2Sign.RecoverOrderSigner: default order buy token")),
            receiver: makeAddr("GPv2Sign.RecoverOrderSigner: default order receiver"),
            sellAmount: 42 ether,
            buyAmount: 13.37 ether,
            validTo: type(uint32).max,
            appData: keccak256("GPv2Sign.RecoverOrderSigner: app data"),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    function test_should_recover_signing_address_for_all_supported_ECDSA_based_schemes() public {
        GPv2Order.Data memory order = defaultOrder();

        Sign.Signature memory eip712Signature = Sign.sign(vm, trader, order, GPv2Signing.Scheme.Eip712, domainSeparator);
        address eip712Owner = executor.recoverOrderSignerTest(order, eip712Signature);
        assertEq(eip712Owner, trader.addr);

        Sign.Signature memory ethSignSignature =
            Sign.sign(vm, trader, order, GPv2Signing.Scheme.EthSign, domainSeparator);
        address ethSignOwner = executor.recoverOrderSignerTest(order, ethSignSignature);
        assertEq(ethSignOwner, trader.addr);
    }

    function test_reverts_for_malformed_ECDSA_signatures() public {
        vm.expectRevert("GPv2: malformed ecdsa signature");
        executor.recoverOrderSignerTest(
            defaultOrder(), Sign.Signature({scheme: GPv2Signing.Scheme.Eip712, data: hex""})
        );
        vm.expectRevert("GPv2: malformed ecdsa signature");
        executor.recoverOrderSignerTest(
            defaultOrder(), Sign.Signature({scheme: GPv2Signing.Scheme.EthSign, data: hex""})
        );
    }

    function test_reverts_for_invalid_eip_712_order_signatures() public {
        Sign.Signature memory signature =
            Sign.sign(vm, trader, defaultOrder(), GPv2Signing.Scheme.Eip712, domainSeparator);

        // NOTE: `v` must be either `27` or `28`, so just set it to something else
        // to generate an invalid signature.
        signature.data[64] = bytes1(0x42);

        vm.expectRevert("GPv2: invalid ecdsa signature");
        executor.recoverOrderSignerTest(defaultOrder(), signature);
    }

    function test_reverts_for_invalid_ethsign_order_signatures() public {
        Sign.Signature memory signature =
            Sign.sign(vm, trader, defaultOrder(), GPv2Signing.Scheme.EthSign, domainSeparator);

        // NOTE: `v` must be either `27` or `28`, so just set it to something else
        // to generate an invalid signature.
        signature.data[64] = bytes1(0x42);

        vm.expectRevert("GPv2: invalid ecdsa signature");
        executor.recoverOrderSignerTest(defaultOrder(), signature);
    }

    function test_should_verify_EIP_1271_contract_signatures_by_returning_owner() public {
        GPv2Order.Data memory order = defaultOrder();
        bytes32 hash = order.hash(domainSeparator);

        bytes memory eip1271SignatureData = hex"031337";
        EIP1271Verifier verifier = EIP1271Verifier(makeAddr("eip1271 verifier"));
        vm.mockCallRevert(address(verifier), hex"", "unexpected call to mock contract");
        vm.mockCall(
            address(verifier),
            abi.encodeCall(EIP1271Verifier.isValidSignature, (hash, eip1271SignatureData)),
            abi.encode(GPv2EIP1271.MAGICVALUE)
        );

        address ethSignOwner = executor.recoverOrderSignerTest(order, Sign.sign(verifier, eip1271SignatureData));
        assertEq(ethSignOwner, address(verifier));
    }

    function test_reverts_on_an_invalid_EIP_1271_signature() public {
        GPv2Order.Data memory order = defaultOrder();
        bytes32 hash = order.hash(domainSeparator);

        bytes memory eip1271SignatureData = hex"031337";
        EIP1271Verifier verifier = EIP1271Verifier(makeAddr("eip1271 verifier rejecting signature"));
        vm.mockCallRevert(address(verifier), hex"", "unexpected call to mock contract");
        vm.mockCall(
            address(verifier),
            abi.encodeCall(EIP1271Verifier.isValidSignature, (hash, eip1271SignatureData)),
            abi.encode(bytes4(0xbaadc0d3))
        );

        vm.expectRevert("GPv2: invalid eip1271 signature");
        executor.recoverOrderSignerTest(order, Sign.sign(verifier, eip1271SignatureData));
    }

    function test_reverts_with_non_standard_EIP_1271_verifiers() public {
        GPv2Order.Data memory order = defaultOrder();
        bytes32 hash = order.hash(domainSeparator);

        bytes memory eip1271SignatureData = hex"031337";
        EIP1271Verifier verifier = EIP1271Verifier(makeAddr("eip1271 verifier no return data"));
        vm.mockCallRevert(address(verifier), hex"", "unexpected call to mock contract");
        vm.mockCall(
            address(verifier), abi.encodeCall(EIP1271Verifier.isValidSignature, (hash, eip1271SignatureData)), hex""
        );

        vm.expectRevert();
        executor.recoverOrderSignerTest(order, Sign.sign(verifier, eip1271SignatureData));
    }

    function test_reverts_for_EIP_1271_signatures_from_externally_owned_accounts() public {
        address verifier = makeAddr("externally owned account");
        vm.expectRevert();
        executor.recoverOrderSignerTest(defaultOrder(), Sign.sign(EIP1271Verifier(verifier), hex"00"));
    }

    function test_reverts_if_the_EIP_1271_verification_function_changes_the_state() public {
        GPv2Order.Data memory order = defaultOrder();
        bytes32 hash = order.hash(domainSeparator);
        StateChangingEIP1271 evilVerifier = new StateChangingEIP1271();
        bytes memory eip1271SignatureData = hex"";

        assertEq(evilVerifier.state(), 0);
        assertEq(evilVerifier.isValidSignature(hash, eip1271SignatureData), EIP1271Verifier.isValidSignature.selector);
        assertEq(evilVerifier.state(), 1);
        vm.expectRevert();
        executor.recoverOrderSignerTest(
            defaultOrder(), Sign.sign(EIP1271Verifier(address(evilVerifier)), eip1271SignatureData)
        );
        assertEq(evilVerifier.state(), 1);
    }

    function test_should_verify_pre_signed_order() public {
        GPv2Order.Data memory order = defaultOrder();
        bytes memory orderUid = Order.computeOrderUid(order, domainSeparator, trader.addr);
        vm.prank(trader.addr);
        executor.setPreSignature(orderUid, true);
        address signer = executor.recoverOrderSignerTest(order, Sign.preSign(trader.addr));
        assertEq(signer, trader.addr);
    }

    function test_reverts_if_order_does_not_have_pre_signature_set() public {
        vm.expectRevert("GPv2: order not presigned");
        executor.recoverOrderSignerTest(defaultOrder(), Sign.preSign(trader.addr));
    }

    function test_should_revert_if_pre_signed_order_is_modified() public {
        GPv2Order.Data memory order = defaultOrder();
        bytes memory orderUid = Order.computeOrderUid(order, domainSeparator, trader.addr);
        vm.prank(trader.addr);
        executor.setPreSignature(orderUid, true);

        order.buyAmount = 0;
        vm.expectRevert("GPv2: order not presigned");
        executor.recoverOrderSignerTest(order, Sign.preSign(trader.addr));
    }

    function test_reverts_for_malformed_pre_sign_order_UID() public {
        vm.expectRevert("GPv2: malformed presignature");
        executor.recoverOrderSignerTest(
            defaultOrder(), Sign.Signature({scheme: GPv2Signing.Scheme.PreSign, data: hex""})
        );
    }
}

/// @dev This contract implements the standard described in EIP-1271 with the
/// minor change that the verification function changes the state. This is
/// forbidden by the standard specifications.
contract StateChangingEIP1271 {
    uint256 public state = 0;

    // solhint-disable-next-line no-unused-vars
    function isValidSignature(bytes32, bytes memory) public returns (bytes4) {
        state += 1;
        return GPv2EIP1271.MAGICVALUE;
    }
}
