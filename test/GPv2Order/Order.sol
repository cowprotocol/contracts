// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Helper} from "./Helper.sol";

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Order.sol";

import {Helper} from "./Helper.sol";
import {Eip712} from "test/libraries/Eip712.sol";
import {Order as OrderLib} from "test/libraries/Order.sol";

contract Order is Helper {
    using Eip712 for GPv2Order.Data;
    using Eip712 for Eip712.Order;

    struct Fuzzed {
        address sellToken;
        address buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
    }

    // Keep track of which order hashes have been seen.
    mapping(bytes32 orderHash => bool) seen;

    function test_TYPE_HASH_matches_the_EIP_712_order_type_hash() public view {
        assertEq(executor.typeHashTest(), Eip712.ORDER_TYPE_HASH());
    }

    function testFuzz_computes_EIP_712_order_signing_hash(Fuzzed memory fuzzed) public {
        bytes32 domainSeparator = keccak256("test domain separator");
        OrderLib.Flags[] memory flags = OrderLib.ALL_FLAGS();
        for (uint256 i = 0; i < flags.length; i++) {
            GPv2Order.Data memory order = GPv2Order.Data({
                sellToken: IERC20(fuzzed.sellToken),
                buyToken: IERC20(fuzzed.buyToken),
                receiver: fuzzed.receiver,
                sellAmount: fuzzed.sellAmount,
                buyAmount: fuzzed.buyAmount,
                validTo: fuzzed.validTo,
                appData: fuzzed.appData,
                feeAmount: fuzzed.feeAmount,
                kind: flags[i].kind,
                partiallyFillable: flags[i].partiallyFillable,
                sellTokenBalance: flags[i].sellTokenBalance,
                buyTokenBalance: flags[i].buyTokenBalance
            });

            bytes32 orderSignignHash = executor.hashTest(order, domainSeparator);
            assertEq(orderSignignHash, order.toEip812SignedStruct().typedDataHash(domainSeparator));
            require(!seen[orderSignignHash], "different flags led to the same hash");
            seen[orderSignignHash] = true;
        }
    }
}
