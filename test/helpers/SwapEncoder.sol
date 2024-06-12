// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {IVault} from "src/contracts/interfaces/IVault.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";
import {GPv2Settlement} from "src/contracts/GPv2Settlement.sol";

import {Sign} from "../libraries/Sign.sol";
import {Trade} from "../libraries/Trade.sol";

import {TokenRegistry} from "./TokenRegistry.sol";

contract SwapEncoder {
    using Trade for GPv2Order.Data;
    using Sign for Vm;

    struct Swap {
        bytes32 poolId;
        IERC20 assetIn;
        IERC20 assetOut;
        uint256 amount;
        bytes userData;
    }

    struct EncodedSwap {
        IVault.BatchSwapStep[] swaps;
        IERC20[] tokens;
        GPv2Trade.Data trade;
    }

    GPv2Settlement internal settlement;
    TokenRegistry internal tokenRegistry;
    IVault.BatchSwapStep[] public steps;
    GPv2Trade.Data public trade;

    constructor(GPv2Settlement _settlement, TokenRegistry _tokenRegistry) {
        settlement = _settlement;
        tokenRegistry = _tokenRegistry;
    }

    function encodeSwapSteps(Swap[] memory swap) public {
        for (uint256 i = 0; i < swap.length; i++) {
            steps.push(toSwapStep(swap[i]));
        }
    }

    function encodeTrade(GPv2Order.Data memory order, Sign.Signature memory signature, uint256 limitAmount) public {
        if (limitAmount == 0) {
            limitAmount = order.kind == GPv2Order.KIND_SELL ? order.buyAmount : order.sellAmount;
        }
        trade = order.toTrade(tokenRegistry.addresses(), signature, limitAmount);
    }

    function signEncodeTrade(
        Vm vm,
        Vm.Wallet memory owner,
        GPv2Order.Data memory order,
        GPv2Signing.Scheme signingScheme,
        uint256 executedAmount
    ) public {
        Sign.Signature memory signature = vm.sign(owner, order, signingScheme, settlement.domainSeparator());
        encodeTrade(order, signature, executedAmount);
    }

    function encodeSwap() public view returns (EncodedSwap memory) {
        return EncodedSwap(steps, tokenRegistry.addresses(), trade);
    }

    function toSwapStep(Swap memory swap) private returns (IVault.BatchSwapStep memory step) {
        step.poolId = swap.poolId;
        step.assetInIndex = tokenRegistry.index(swap.assetIn);
        step.assetOutIndex = tokenRegistry.index(swap.assetOut);
        step.amount = swap.amount;
        step.userData = swap.userData;
    }
}
