// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

import {GPv2Order, IERC20} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Trade} from "src/contracts/libraries/GPv2Trade.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";
import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";
import {GPv2Settlement} from "src/contracts/GPv2Settlement.sol";

import {Sign} from "test/libraries/Sign.sol";
import {Trade} from "test/libraries/Trade.sol";

import {TokenRegistry} from "./TokenRegistry.sol";

contract SettlementEncoder {
    using GPv2Order for GPv2Order.Data;
    using Trade for GPv2Order.Data;
    using Sign for Vm;

    /// The stage an interaction should be executed in
    enum InteractionStage {
        PRE,
        INTRA,
        POST
    }

    /**
     * Order refund data.
     *
     * @dev after the London hardfork (specifically the introduction of EIP-3529)
     * order refunds have become meaningless as the refunded amount is less than the
     * gas cost of triggering the refund. The logic surrounding this feature is kept
     * in order to keep full test coverage and in case the value of a refund will be
     * increased again in the future. However, order refunds should not be used in
     * an actual settlement.
     */
    struct OrderRefunds {
        bytes[] filledAmounts;
        bytes[] preSignatures;
    }

    /// Encoded settlement parameters
    struct EncodedSettlement {
        IERC20[] tokens;
        uint256[] clearingPrices;
        GPv2Trade.Data[] trades;
        GPv2Interaction.Data[][3] interactions;
    }

    error InvalidOrderUidLength();

    GPv2Settlement public settlement;
    TokenRegistry internal tokenRegistry;
    GPv2Trade.Data[] public trades;
    GPv2Interaction.Data[][3] private interactions_;
    OrderRefunds private refunds;

    constructor(GPv2Settlement _settlement, TokenRegistry _tokenRegistry) {
        settlement = _settlement;
        tokenRegistry = (_tokenRegistry == TokenRegistry(address(0)) ? new TokenRegistry() : _tokenRegistry);
    }

    function tokens() public view returns (IERC20[] memory) {
        return tokenRegistry.addresses();
    }

    function interactions() public view returns (GPv2Interaction.Data[][3] memory) {
        GPv2Interaction.Data[] memory r = encodeOrderRefunds();
        GPv2Interaction.Data[] memory postInteractions =
            new GPv2Interaction.Data[](interactions_[uint256(InteractionStage.POST)].length + r.length);

        for (uint256 i = 0; i < interactions_[uint256(InteractionStage.POST)].length; i++) {
            postInteractions[i] = interactions_[uint256(InteractionStage.POST)][i];
        }

        for (uint256 i = 0; i < r.length; i++) {
            postInteractions[interactions_[uint256(InteractionStage.POST)].length + i] = r[i];
        }

        return [
            interactions_[uint256(InteractionStage.PRE)],
            interactions_[uint256(InteractionStage.INTRA)],
            postInteractions
        ];
    }

    uint256 public constant ZERO_EXECUTED_AMOUNT = uint256(keccak256("ZERO_EXECUTED_AMOUNT"));

    function encodeTrade(GPv2Order.Data memory order, Sign.Signature memory signature, uint256 executedAmount) public {
        executedAmount = executedAmount == 0 ? ZERO_EXECUTED_AMOUNT : executedAmount;
        trades.push(order.toTrade(tokenRegistry.addresses(), signature, executedAmount));
    }

    function signEncodeOrder(
        Vm vm,
        Vm.Wallet memory owner,
        GPv2Order.Data memory order,
        GPv2Signing.Scheme signingScheme,
        uint256 executedAmount
    ) public {
        Sign.Signature memory signature = vm.toSignature(owner, order, signingScheme, settlement.domainSeparator());
        encodeTrade(order, signature, executedAmount);
    }

    function addInteraction(GPv2Interaction.Data memory interaction, InteractionStage stage) public {
        interactions_[uint256(stage)].push(interaction);
    }

    function addOrderRefunds(OrderRefunds memory orderRefunds) public {
        if (orderRefunds.filledAmounts.length > 0) {
            for (uint256 i = 0; i < orderRefunds.filledAmounts.length; i++) {
                bytes memory filledAmount = orderRefunds.filledAmounts[i];
                if (filledAmount.length != GPv2Order.UID_LENGTH) {
                    revert InvalidOrderUidLength();
                }
                refunds.filledAmounts.push(filledAmount);
            }
        }

        if (orderRefunds.preSignatures.length > 0) {
            for (uint256 i = 0; i < orderRefunds.preSignatures.length; i++) {
                bytes memory preSignature = orderRefunds.preSignatures[i];
                if (preSignature.length != GPv2Order.UID_LENGTH) {
                    revert InvalidOrderUidLength();
                }
                refunds.preSignatures.push(preSignature);
            }
        }
    }

    function toEncodedSettlement() public view returns (EncodedSettlement memory) {
        return EncodedSettlement({
            tokens: tokens(),
            clearingPrices: tokenRegistry.clearingPrices(),
            trades: trades,
            interactions: interactions()
        });
    }

    function toEncodedSettlement(GPv2Interaction.Data[] memory setupInteractions)
        public
        pure
        returns (EncodedSettlement memory)
    {
        return EncodedSettlement({
            tokens: new IERC20[](0),
            clearingPrices: new uint256[](0),
            trades: new GPv2Trade.Data[](0),
            interactions: [new GPv2Interaction.Data[](0), setupInteractions, new GPv2Interaction.Data[](0)]
        });
    }

    function encodeOrderRefunds() private view returns (GPv2Interaction.Data[] memory _refunds) {
        if (refunds.filledAmounts.length + refunds.preSignatures.length == 0) {
            return new GPv2Interaction.Data[](0);
        }

        uint256 numInteractions =
            (refunds.filledAmounts.length > 0 ? 1 : 0) + (refunds.preSignatures.length > 0 ? 1 : 0);
        _refunds = new GPv2Interaction.Data[](numInteractions);

        uint256 i = 0;
        if (refunds.filledAmounts.length > 0) {
            _refunds[i++] = refundFnEncoder(GPv2Settlement.freeFilledAmountStorage.selector, refunds.filledAmounts);
        }

        if (refunds.preSignatures.length > 0) {
            _refunds[i] = refundFnEncoder(GPv2Settlement.freePreSignatureStorage.selector, refunds.preSignatures);
        }
    }

    function refundFnEncoder(bytes4 fn, bytes[] memory orderUids) private view returns (GPv2Interaction.Data memory) {
        return GPv2Interaction.Data({
            target: address(settlement),
            value: 0,
            callData: abi.encodeWithSelector(fn, orderUids)
        });
    }
}
