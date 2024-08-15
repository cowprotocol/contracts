// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {GPv2Order, GPv2Signing, GPv2Trade, IERC20, Order, Trade} from "test/libraries/Trade.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

contract Harness {
    function extractOrderTest(IERC20[] calldata tokens, GPv2Trade.Data calldata trade)
        external
        pure
        returns (GPv2Order.Data memory order)
    {
        GPv2Trade.extractOrder(trade, tokens, order);
    }

    function extractFlagsStructuredTest(uint256 flags) external pure returns (Trade.Flags memory) {
        (
            bytes32 kind,
            bool partiallyFillable,
            bytes32 sellTokenBalance,
            bytes32 buyTokenBalance,
            GPv2Signing.Scheme signingScheme
        ) = GPv2Trade.extractFlags(flags);
        Order.Flags memory orderFlags = Order.Flags({
            kind: kind,
            sellTokenBalance: sellTokenBalance,
            buyTokenBalance: buyTokenBalance,
            partiallyFillable: partiallyFillable
        });
        return Trade.Flags({flags: orderFlags, signingScheme: signingScheme});
    }
}

contract Helper is Test {
    Harness internal executor;
    Vm.Wallet internal trader = vm.createWallet("GPv2Trade.Helper trader");
    bytes32 internal domainSeparator = keccak256("GPv2Trade.Helper domain separator");
    SettlementEncoder.State internal encoder;

    function setUp() public {
        executor = new Harness();
        encoder = SettlementEncoder.makeSettlementEncoder();
    }
}
