// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2SettlementHelper} from "./GPv2SettlementHelper.sol";
import {SettlementEncoder} from "test/helpers/SettlementEncoder.sol";
import {TokenRegistry} from "test/helpers/TokenRegistry.sol";

// solhint-disable func-name-mixedcase
contract SettleTest is GPv2SettlementHelper {

    SettlementEncoder internal encoder;

    function setUp() public override {
        super.setUp();
        encoder = new SettlementEncoder(settlement, TokenRegistry(address(0)));
    }

    function test_rejects_transactions_from_non_solvers() public {
        SettlementEncoder.EncodedSettlement memory encoded = encoder.toEncodedSettlement();
        vm.expectRevert("GPv2: not a solver");
        settlement.settle(
            encoded.tokens,
            encoded.clearingPrices,
            encoded.trades,
            encoded.interactions
        );
    }

    function test_reentrancy_protection() public {
        
    }

}
