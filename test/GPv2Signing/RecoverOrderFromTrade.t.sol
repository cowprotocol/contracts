// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {EIP1271Verifier, GPv2EIP1271, GPv2Order, GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Helper} from "./Helper.sol";
import {Order} from "test/libraries/Order.sol";
import {OrderFuzz} from "test/libraries/OrderFuzz.sol";
import {Sign} from "test/libraries/Sign.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";

contract RecoverOrderFromTrade is Helper {
    using SettlementEncoder for SettlementEncoder.State;
    using Sign for EIP1271Verifier;

    Vm.Wallet private trader;

    constructor() {
        trader = vm.createWallet("GPv2Signing.RecoverOrderFromTrade: trader");
    }

    function test_should_round_trip_encode_order_data_and_unique_identifier(
        OrderFuzz.Params memory params,
        uint256 executedAmount
    ) public {
        GPv2Order.Data memory order = OrderFuzz.order(params);

        SettlementEncoder.State storage encoder = SettlementEncoder.makeSettlementEncoder();
        encoder.signEncodeTrade(vm, trader, order, domainSeparator, GPv2Signing.Scheme.Eip712, executedAmount);

        GPv2Signing.RecoveredOrder memory recovered =
            executor.recoverOrderFromTradeTest(encoder.tokens(), encoder.trades[0]);
        assertEq(abi.encode(recovered.data), abi.encode(order));
        assertEq(recovered.uid, Order.computeOrderUid(order, domainSeparator, trader.addr));
    }

    function test_should_recover_the_order_for_all_signing_schemes(OrderFuzz.Params memory params) public {
        GPv2Order.Data memory order = OrderFuzz.order(params);

        address traderPreSign = makeAddr("trader pre-sign");
        EIP1271Verifier traderEip1271 = EIP1271Verifier(makeAddr("eip1271 verifier"));
        Vm.Wallet memory traderEip712 = vm.createWallet("trader eip712");
        Vm.Wallet memory traderEthsign = vm.createWallet("trader ethsign");

        bytes memory uidPreSign = Order.computeOrderUid(order, domainSeparator, traderPreSign);
        vm.prank(traderPreSign);
        executor.setPreSignature(uidPreSign, true);

        vm.mockCallRevert(address(traderEip1271), hex"", "unexpected call to mock contract");
        vm.mockCall(
            address(traderEip1271),
            abi.encodePacked(EIP1271Verifier.isValidSignature.selector),
            abi.encode(GPv2EIP1271.MAGICVALUE)
        );

        SettlementEncoder.State storage encoder = SettlementEncoder.makeSettlementEncoder();
        encoder.encodeTrade(order, Sign.preSign(traderPreSign), 0);
        encoder.encodeTrade(order, Sign.sign(traderEip1271, hex""), 0);
        encoder.signEncodeTrade(vm, traderEip712, order, domainSeparator, GPv2Signing.Scheme.Eip712, 0);
        encoder.signEncodeTrade(vm, traderEthsign, order, domainSeparator, GPv2Signing.Scheme.EthSign, 0);

        GPv2Signing.RecoveredOrder memory recovered;
        recovered = executor.recoverOrderFromTradeTest(encoder.tokens(), encoder.trades[0]);
        assertEq(recovered.owner, traderPreSign);
        recovered = executor.recoverOrderFromTradeTest(encoder.tokens(), encoder.trades[1]);
        assertEq(recovered.owner, address(traderEip1271));
        recovered = executor.recoverOrderFromTradeTest(encoder.tokens(), encoder.trades[2]);
        assertEq(recovered.owner, traderEip712.addr);
        recovered = executor.recoverOrderFromTradeTest(encoder.tokens(), encoder.trades[3]);
        assertEq(recovered.owner, traderEthsign.addr);
    }
}
