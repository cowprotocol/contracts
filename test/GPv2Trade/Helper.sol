// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {GPv2Signing, GPv2Trade, Order, Trade} from "test/libraries/Trade.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";
import {GPv2TradeTestInterface} from "test/src/GPv2TradeTestInterface.sol";

// TODO: move the content of `GPv2TradeTestInterface` here once all tests have been removed.
// solhint-disable-next-line no-empty-blocks
contract Harness is GPv2TradeTestInterface {
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
