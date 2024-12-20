// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {GPv2Order, GPv2Signing, SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

contract WineOilTest is Helper(false) {
    IERC20Mintable eur;
    IERC20Mintable oil;
    IERC20Mintable wine;

    uint256 constant STARTING_BALANCE = 1000 ether;

    function setUp() public override {
        super.setUp();

        eur = deployMintableErc20("eur", "eur");
        oil = deployMintableErc20("oil", "oil");
        wine = deployMintableErc20("wine", "wine");
    }

    // Settlement for the RetrETH wine and olive oil market:
    //
    //  /---(6. BUY 10 🍷 with 💶 if p(🍷) <= 13)--> [🍷]
    //  |                                             |
    //  |                                             |
    // [💶]                        (1. SELL 12 🍷 for 🫒 if p(🍷) >= p(🫒))
    //  |^                                            |
    //  ||                                            |
    //  |\--(4. SELL 15 🫒 for 💶 if p(🫒) >= 12)--\  v
    //  \---(5. BUY 4 🫒 with 💶 if p(🫒) <= 13)---> [🫒]
    function test_should_settle_red_wine_and_olive_oil_market() external {
        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");
        Vm.Wallet memory trader3 = vm.createWallet("trader3");
        Vm.Wallet memory trader4 = vm.createWallet("trader4");
        uint256 feeAmount = 1 ether;

        // sell 12 wine for min 12 oil
        _createOrder(
            trader1,
            _orderData({
                sellToken: wine,
                buyToken: oil,
                sellAmount: 12 ether,
                buyAmount: 12 ether,
                feeAmount: feeAmount,
                orderKind: GPv2Order.KIND_SELL,
                partiallyFillable: false
            }),
            0
        );
        // sell 15 oil for min 180 eur
        _createOrder(
            trader2,
            _orderData({
                sellToken: oil,
                buyToken: eur,
                sellAmount: 15 ether,
                buyAmount: 180 ether,
                feeAmount: feeAmount,
                orderKind: GPv2Order.KIND_SELL,
                partiallyFillable: false
            }),
            0
        );
        // buy 4 oil with max 52 eur
        uint256 order3ExecutedAmount = uint256(27 ether) / 13;
        _createOrder(
            trader3,
            _orderData({
                sellToken: eur,
                buyToken: oil,
                sellAmount: 52 ether,
                buyAmount: 4 ether,
                feeAmount: feeAmount,
                orderKind: GPv2Order.KIND_BUY,
                partiallyFillable: true
            }),
            order3ExecutedAmount
        );
        // buy 20 wine with max 280 eur
        uint256 order4ExecutedAmount = 12 ether;
        _createOrder(
            trader4,
            _orderData({
                sellToken: eur,
                buyToken: wine,
                sellAmount: 280 ether,
                buyAmount: 20 ether,
                feeAmount: feeAmount,
                orderKind: GPv2Order.KIND_BUY,
                partiallyFillable: true
            }),
            order4ExecutedAmount
        );

        uint256 oilPrice = 13 ether;
        uint256 winePrice = 14 ether;
        {
            // set token prices
            IERC20[] memory tokens = new IERC20[](3);
            tokens[0] = eur;
            tokens[1] = oil;
            tokens[2] = wine;
            uint256[] memory prices = new uint256[](3);
            prices[0] = 1 ether;
            prices[1] = oilPrice;
            prices[2] = winePrice;

            encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);
        }

        // settle the orders
        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);
        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(
            wine.balanceOf(trader1.addr),
            STARTING_BALANCE - 12 ether - feeAmount,
            "trader1 sold token amounts not as expected"
        );
        uint256 trader1AmountOut = ceilDiv(uint256(12 ether * 14 ether), 13 ether);
        assertEq(oil.balanceOf(trader1.addr), trader1AmountOut, "trader1 amountOut not as expected");

        assertEq(
            oil.balanceOf(trader2.addr),
            STARTING_BALANCE - 15 ether - feeAmount,
            "trader2 sold token amounts not as expected"
        );
        assertEq(eur.balanceOf(trader2.addr), 15 ether * 13, "trader2 amountOut not as expected");

        // order: buy 4 oil with max 52 eur, partial execution
        uint256 order3SellAmount = order3ExecutedAmount * oilPrice / 1 ether;
        uint256 order3FeeAmount = feeAmount * order3ExecutedAmount / 4 ether;
        assertEq(
            eur.balanceOf(trader3.addr),
            STARTING_BALANCE - order3SellAmount - order3FeeAmount,
            "trader3 sold token amount not as expected"
        );
        assertEq(oil.balanceOf(trader3.addr), order3ExecutedAmount, "trader3 amountOut not as expected");

        // order: buy 20 wine with max 280 eur, partial execution
        uint256 order4SellAmount = order4ExecutedAmount * winePrice / 1 ether;
        uint256 order4FeeAmount = feeAmount * order4ExecutedAmount / 20 ether;
        assertEq(
            eur.balanceOf(trader4.addr),
            STARTING_BALANCE - order4SellAmount - order4FeeAmount,
            "trader4 sold token amount not as expected"
        );
        assertEq(wine.balanceOf(trader4.addr), order4ExecutedAmount, "trader4 amountOut not as expected");
    }

    function _createOrder(Vm.Wallet memory wallet, GPv2Order.Data memory order, uint256 executedAmount) internal {
        IERC20Mintable(address(order.sellToken)).mint(wallet.addr, STARTING_BALANCE);
        vm.prank(wallet.addr);
        order.sellToken.approve(vaultRelayer, type(uint256).max);

        encoder.signEncodeTrade(vm, wallet, order, domainSeparator, GPv2Signing.Scheme.Eip712, executedAmount);
    }

    function _orderData(
        IERC20 sellToken,
        IERC20 buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 feeAmount,
        bytes32 orderKind,
        bool partiallyFillable
    ) internal pure returns (GPv2Order.Data memory order) {
        order = GPv2Order.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: 0xffffffff,
            appData: bytes32(uint256(1)),
            feeAmount: feeAmount,
            kind: orderKind,
            partiallyFillable: partiallyFillable,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }

    function ceilDiv(uint256 num, uint256 den) internal pure returns (uint256) {
        return num % den == 0 ? num / den : (num / den) + 1;
    }
}
