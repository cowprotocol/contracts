// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Harness} from "test/GPv2Signing/Helper.sol";

import {Bytes} from "./Bytes.sol";

type Owner is address;

type PreSignSignature is address;

library Sign {
    using GPv2Order for GPv2Order.Data;
    using GPv2Trade for uint256;
    using Bytes for bytes;

    // Copied from GPv2Signing.sol
    uint256 internal constant PRE_SIGNED = uint256(keccak256("GPv2Signing.Scheme.PreSign"));

    struct Signature {
        /// @dev The signing scheme used in this signature
        GPv2Signing.Scheme scheme;
        /// @dev The signature data specific to the signing scheme
        bytes data;
    }

    struct Eip1271Signature {
        address verifier;
        bytes signature;
    }

    /// @dev Encode and sign the order using the provided signing scheme (EIP-712 or EthSign)
    function toSignature(
        Vm vm,
        Vm.Wallet memory owner,
        GPv2Signing.Scheme scheme,
        bytes32 domainSeparator,
        GPv2Order.Data memory order
    ) internal returns (Signature memory signature) {
        bytes32 hash = order.hash(domainSeparator);
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (scheme == GPv2Signing.Scheme.Eip712) {
            (v, r, s) = vm.sign(owner, hash);
        } else if (scheme == GPv2Signing.Scheme.EthSign) {
            (v, r, s) = vm.sign(owner, toEthSignedMessageHash(hash));
        } else {
            revert(
                "Cannot create a signature for the specified signature scheme, only ECDSA-based schemes are supported"
            );
        }

        signature.data = abi.encodePacked(r, s, v);
        signature.scheme = scheme;
    }

    /// @dev Encode the data used to verify a pre-signed signature
    function toSignature(PreSignSignature preSign) internal pure returns (Signature memory) {
        return Signature(GPv2Signing.Scheme.PreSign, abi.encodePacked(preSign));
    }

    /// @dev Decode the data used to verify a pre-signed signature
    function toPreSignSignature(Signature memory encodedSignature) internal pure returns (PreSignSignature) {
        if (encodedSignature.scheme != GPv2Signing.Scheme.PreSign) {
            revert("Cannot create a signature for the specified signature scheme, only PreSign is supported");
        }

        return PreSignSignature.wrap(abi.decode(encodedSignature.data, (address)));
    }

    /// @dev Encodes the necessary data required to verify an EIP-1271 signature
    function toSignature(Eip1271Signature memory eip1271Signature) internal pure returns (Signature memory) {
        return Signature(
            GPv2Signing.Scheme.Eip1271, abi.encodePacked(eip1271Signature.verifier, eip1271Signature.signature)
        );
    }

    /// @dev Decodes the data used to verify an EIP-1271 signature
    function toEip1271Signature(Signature memory encodedSignature) internal pure returns (Eip1271Signature memory) {
        if (encodedSignature.scheme != GPv2Signing.Scheme.Eip1271) {
            revert("Cannot create a signature for the specified signature scheme, only EIP-1271 is supported");
        }

        address verifier;
        uint256 length = encodedSignature.data.length - 20;
        bytes memory signature = encodedSignature.data.slice(20, length);

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            let ptr := add(encodedSignature, 0x40)
            verifier := shr(96, mload(add(ptr, 0x20)))
        }

        return Eip1271Signature(verifier, signature);
    }

    function toUint256(GPv2Signing.Scheme signingScheme) internal pure returns (uint256 encodedFlags) {
        // GPv2Signing.Scheme.EIP712 = 0 (default)
        if (signingScheme == GPv2Signing.Scheme.EthSign) {
            encodedFlags |= 1 << 5;
        } else if (signingScheme == GPv2Signing.Scheme.Eip1271) {
            encodedFlags |= 2 << 5;
        } else if (signingScheme == GPv2Signing.Scheme.PreSign) {
            encodedFlags |= 3 << 5;
        }
    }

    function toSigningScheme(uint256 encodedFlags) internal pure returns (GPv2Signing.Scheme signingScheme) {
        (,,,, signingScheme) = encodedFlags.extractFlags();
    }

    function toOwner(Harness exposed, GPv2Order.Data memory order, Sign.Signature memory signature)
        internal
        view
        returns (Owner)
    {
        (, address owner) = exposed.exposed_recoverOrderSigner(order, signature.scheme, signature.data);
        return Owner.wrap(owner);
    }

    /// @dev Internal helper function for EthSign signatures (non-EIP-712)
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 ethSignDigest) {
        ethSignDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}
