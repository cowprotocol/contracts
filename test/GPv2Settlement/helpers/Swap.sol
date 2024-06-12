// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {IERC20, IVault, GPv2Order, GPv2Trade, GPv2Signing, GPv2Settlement} from "src/contracts/GPv2Settlement.sol";

import {Sign} from "test/libraries/Sign.sol";
import {Trade} from "test/libraries/Trade.sol";

import {TokenRegistry} from "./TokenRegistry.sol";

abstract contract Swap is TokenRegistry {
    using Trade for GPv2Order.Data;
    using Sign for Vm;

    struct VaultSwap {
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

    IVault.BatchSwapStep[] public steps;
    GPv2Trade.Data public trade;

    function encodeSwapSteps(VaultSwap[] memory _swap) public {
        for (uint256 i = 0; i < _swap.length; i++) {
            steps.push(toSwapStep(_swap[i]));
        }
    }

    function encodeTrade(GPv2Order.Data memory order, Sign.Signature memory signature, uint256 limitAmount) public {
        if (limitAmount == 0) {
            limitAmount = order.kind == GPv2Order.KIND_SELL ? order.buyAmount : order.sellAmount;
        }
        trade = order.toTrade(tokens(), signature, limitAmount);
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

    function encode() public view returns (EncodedSwap memory) {
        return EncodedSwap(steps, tokens(), trade);
    }

    function toSwapStep(VaultSwap memory _swap) private returns (IVault.BatchSwapStep memory step) {
        step.poolId = _swap.poolId;
        step.assetInIndex = indexOf(_swap.assetIn);
        step.assetOutIndex = indexOf(_swap.assetOut);
        step.amount = _swap.amount;
        step.userData = _swap.userData;
    }

    function swap(EncodedSwap memory _swap) internal {
        settlement.swap(_swap.swaps, _swap.tokens, _swap.trade);
    }

    function swap(GPv2Settlement settler, EncodedSwap memory _swap) internal {
        settler.swap(_swap.swaps, _swap.tokens, _swap.trade);
    }
}
