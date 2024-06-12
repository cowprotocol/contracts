// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {GPv2Order, GPv2Trade, GPv2Signing} from "src/contracts/GPv2Settlement.sol";

import {Harness} from "../Helper.sol";
import {Sign} from "test/libraries/Sign.sol";
import {Trade} from "test/libraries/Trade.sol";

import {TokenRegistry} from "./TokenRegistry.sol";

abstract contract Encoder is TokenRegistry {
    using Trade for GPv2Order.Data;
    using Sign for Vm;

    GPv2Trade.Data[] public trades;

    function encodeTrade(GPv2Order.Data memory order, Sign.Signature memory signature, uint256 executedAmount)
        public
        virtual
    {
        trades.push(order.toTrade(tokens(), signature, executedAmount));
    }

    function signEncodeTrade(
        Vm vm,
        Vm.Wallet memory owner,
        GPv2Order.Data memory order,
        GPv2Signing.Scheme signingScheme,
        uint256 executedAmount
    ) public {
        Sign.Signature memory signature = vm.sign(owner, order, signingScheme, domainSeparator);
        encodeTrade(order, signature, executedAmount);
    }

    function setDomainSeparator(bytes32 _domainSeparator) public {
        domainSeparator = _domainSeparator;
    }
}
