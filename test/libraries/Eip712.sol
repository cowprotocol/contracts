// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

library Eip712 {
    /// EIP-712 domain information (a.k.a. "domain separator"). The salt
    /// parameter is intentionally omitted as there is no need to disambiguate
    /// with the available information. More details can be found at:
    /// https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator
    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    // This is the struct representing an order that is signed by the user using
    // EIP-712.
    struct Order {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        string kind;
        bool partiallyFillable;
        string sellTokenBalance;
        string buyTokenBalance;
    }

    // Ideally, this would be replaced by type(EIP712Domain).typehash.
    // Progress tracking for this Solidity feature is here:
    // https://github.com/ethereum/solidity/issues/14157
    function EIP712DOMAIN_TYPE_HASH() internal pure returns (bytes32) {
        return keccak256(
            bytes(
                string.concat(
                    // Should reflect the definition of the struct `EIP712Domain`.
                    "EIP712Domain(",
                    "string name,",
                    "string version,",
                    "uint256 chainId,",
                    "address verifyingContract",
                    ")"
                )
            )
        );
    }

    // Ideally, this would be replaced by type(Order).typehash.
    // Progress tracking for this Solidity feature is here:
    // https://github.com/ethereum/solidity/issues/14157
    function ORDER_TYPE_HASH() internal pure returns (bytes32) {
        return keccak256(
            bytes(
                string.concat(
                    // Should reflect the definition of the struct `Order`.
                    "Order(",
                    "address sellToken,",
                    "address buyToken,",
                    "address receiver,",
                    "uint256 sellAmount,",
                    "uint256 buyAmount,",
                    "uint32 validTo,",
                    "bytes32 appData,",
                    "uint256 feeAmount,",
                    "string kind,",
                    "bool partiallyFillable,",
                    "string sellTokenBalance,",
                    "string buyTokenBalance",
                    ")"
                )
            )
        );
    }

    function toKindString(bytes32 orderKind) internal pure returns (string memory) {
        if (orderKind == GPv2Order.KIND_SELL) {
            return "sell";
        } else if (orderKind == GPv2Order.KIND_BUY) {
            return "buy";
        } else {
            revert("invalid order kind identifier");
        }
    }

    function toSellTokenBalanceString(bytes32 balanceType) private pure returns (string memory) {
        return toTokenBalanceString(balanceType, true);
    }

    function toBuyTokenBalanceString(bytes32 balanceType) private pure returns (string memory) {
        return toTokenBalanceString(balanceType, false);
    }

    function toTokenBalanceString(bytes32 balanceType, bool isSell) internal pure returns (string memory) {
        if (balanceType == GPv2Order.BALANCE_ERC20) {
            return "erc20";
        } else if (balanceType == GPv2Order.BALANCE_EXTERNAL) {
            require(isSell, "external order kind is only supported for sell balance");
            return "external";
        } else if (balanceType == GPv2Order.BALANCE_INTERNAL) {
            return "internal";
        } else {
            revert("invalid order kind identifier");
        }
    }

    function toEip712SignedStruct(GPv2Order.Data memory order) internal pure returns (Order memory) {
        return Order({
            sellToken: address(order.sellToken),
            buyToken: address(order.buyToken),
            receiver: order.receiver,
            sellAmount: order.sellAmount,
            buyAmount: order.buyAmount,
            validTo: order.validTo,
            appData: order.appData,
            feeAmount: order.feeAmount,
            kind: toKindString(order.kind),
            partiallyFillable: order.partiallyFillable,
            sellTokenBalance: toSellTokenBalanceString(order.sellTokenBalance),
            buyTokenBalance: toBuyTokenBalanceString(order.buyTokenBalance)
        });
    }

    function hashStruct(EIP712Domain memory domain) internal pure returns (bytes32) {
        // Ideally, this would be replaced by `domain.hashStruct()`.
        // Progress tracking for this Solidity feature is here:
        // https://github.com/ethereum/solidity/issues/14208
        return keccak256(
            // Note: dynamic types are hashed.
            abi.encode(
                EIP712DOMAIN_TYPE_HASH(),
                keccak256(bytes(domain.name)),
                keccak256(bytes(domain.version)),
                domain.chainId,
                domain.verifyingContract
            )
        );
    }

    function hashStruct(Order memory order) internal pure returns (bytes32) {
        // Ideally, this would be replaced by `order.hashStruct()`.
        // Progress tracking for this Solidity feature is here:
        // https://github.com/ethereum/solidity/issues/14208
        return keccak256(
            // Note: dynamic types are hashed.
            abi.encode(
                ORDER_TYPE_HASH(),
                order.sellToken,
                order.buyToken,
                order.receiver,
                order.sellAmount,
                order.buyAmount,
                order.validTo,
                order.appData,
                order.feeAmount,
                keccak256(bytes(order.kind)),
                order.partiallyFillable,
                keccak256(bytes(order.sellTokenBalance)),
                keccak256(bytes(order.buyTokenBalance))
            )
        );
    }

    // Ideally, this would be replaced by a dedicated function in Solidity.
    // This is currently not planned but it could be once `typehash` and
    // `hashStruct` are introduced.
    function typedDataHash(Order memory order, bytes32 domainSeparator) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashStruct(order)));
    }
}
