// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {GPv2Order, GPv2Signing, IERC20} from "src/contracts/mixins/GPv2Signing.sol";

import {GPv2SigningTestInterface, Helper} from "./Helper.sol";

import {Bytes} from "test/libraries/Bytes.sol";
import {Order} from "test/libraries/Order.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

contract CalldataManipulation is Helper {
    using SettlementEncoder for SettlementEncoder.State;
    using Bytes for bytes;

    Vm.Wallet private trader;

    constructor() {
        trader = vm.createWallet("GPv2Signing.RecoverOrderFromTrade: trader");
    }

    function test_invalid_EVM_transaction_encoding_does_not_change_order_hash(
        Order.Fuzzed memory params,
        uint256 paddingIndex
    ) public {
        // The variables for an EVM transaction are encoded in multiples of 32
        // bytes for all types except `string` and `bytes`. This extra padding
        // is usually filled with zeroes by the library that creates the
        // transaction. It can however be manually messed with.
        // Since Solidity v0.8, using nonzero padding should cause the
        // transaction to revert.
        // Computing GPv2's orderUid requires copying 32-byte-encoded addresses
        // from calldata to memory (buy and sell tokens), which are then hashed
        // together with the rest of the order. This copying procedure would
        // keep the padding bytes as they are in the (manipulated) calldata.
        // If these 12 padding bits were not zero after copying, then the same
        // order would end up with two different uids. This test shows that this
        // is not the case by showing that such calldata manipulation causes the
        // transaction to revert.

        GPv2Order.Data memory order = Order.fuzz(params);

        SettlementEncoder.State storage encoder = SettlementEncoder.makeSettlementEncoder();
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, 0);

        IERC20[] memory tokens = encoder.tokens();
        bytes memory encodedTransactionData =
            abi.encodeCall(GPv2SigningTestInterface.recoverOrderFromTradeTest, (tokens, encoder.trades[0]));

        // calldata encoding:
        //  -  4 bytes: signature
        //  - 32 bytes: pointer to first input value
        //  - 32 bytes: pointer to second input value
        //  - 32 bytes: first input value, array -> token array length
        //  - 32 bytes: first token address
        uint256 startNumTokenWord = 4 + 2 * 32;
        uint256 startFirstTokenWord = startNumTokenWord + 32;
        uint256 encodedNumTokens = abi.decode(encodedTransactionData.slice(startNumTokenWord, 32), (uint256));
        require(
            encodedNumTokens == ((order.sellToken == order.buyToken) ? 1 : 2),
            "invalid test setup; has the transaction encoding changed?"
        );
        bytes memory encodedFirstToken = encodedTransactionData.slice(startFirstTokenWord, 32);
        uint256 tokenPaddingSize = 12;
        for (uint256 i = 0; i < tokenPaddingSize; i++) {
            require(encodedFirstToken[i] == bytes1(0), "invalid test setup; has the transaction encoding changed?");
        }
        IERC20 token = IERC20(abi.decode(encodedFirstToken, (address)));
        require(token == tokens[0], "invalid test setup; has the transaction encoding changed?");
        // Here we change a single padding byte, this is enough to make the
        // transaction revert.
        paddingIndex = paddingIndex % tokenPaddingSize;
        encodedTransactionData[startFirstTokenWord + paddingIndex] = 0x42;
        // Using low-level call because we want to call this function with data
        // that is intentionally invalid.
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(executor).call(encodedTransactionData);
        assertFalse(success);
    }
}
