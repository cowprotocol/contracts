// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2Transfer} from "src/contracts/libraries/GPv2Transfer.sol";

import {
    GPv2Interaction,
    GPv2Order,
    GPv2Signing,
    GPv2Trade,
    SettlementEncoder
} from "test/libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "test/libraries/encoders/TokenRegistry.sol";

import {Helper} from "./Helper.sol";

interface IUSDT {
    function getOwner() external view returns (address);
    function issue(uint256) external;
    // approve and transfer doesn't return the bool for USDT
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
}

IUSDT constant USDT = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

contract BuyEthTest is Helper(true) {
    // Settle a trivial batch between two overlapping trades:
    //
    //   /----(1. SELL 1 WETH for USDT if p(WETH) >= 1100)----\
    //   |                                                    v
    // [USDT]                                              [(W)ETH]
    //   ^                                                    |
    //   \-----(2. BUY 1 ETH for USDT if p(WETH) <= 1200)-----/
    function test_should_unwrap_weth_for_eth_buy_orders() external {
        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");

        // give some weth to trader1
        deal(address(WETH), trader1.addr, 1.001 ether);
        // approve weth for trading on the vault
        vm.prank(trader1.addr);
        WETH.approve(vaultRelayer, type(uint256).max);
        // place the weth to usdt swap order
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                sellToken: WETH,
                buyToken: IERC20(address(USDT)),
                receiver: trader1.addr,
                sellAmount: 1 ether,
                buyAmount: 1100e6,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0.001 ether,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // give some usdt to trader2
        _mintUsdt(trader2.addr, 1201.2e6);
        // approve usdt for trading on the vault
        vm.startPrank(trader2.addr);
        USDT.approve(vaultRelayer, 0);
        USDT.approve(vaultRelayer, type(uint256).max);
        vm.stopPrank();
        // place the usdt to eth swap order
        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                sellToken: IERC20(address(USDT)),
                buyToken: IERC20(GPv2Transfer.BUY_ETH_ADDRESS),
                receiver: trader2.addr,
                sellAmount: 1200e6,
                buyAmount: 1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 1.2e6,
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // encode the weth withdraw interaction
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(WETH),
                value: 0,
                callData: abi.encodeWithSignature("withdraw(uint256)", 1 ether)
            }),
            SettlementEncoder.InteractionStage.INTRA
        );

        // set the token prices
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = WETH;
        tokens[1] = IERC20(GPv2Transfer.BUY_ETH_ADDRESS);
        tokens[2] = IERC20(address(USDT));
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1150e6;
        prices[1] = 1150e6;
        prices[2] = 1 ether;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);

        uint256 trader2InitialBalance = trader2.addr.balance;
        vm.prank(solver);
        settle(encodedSettlement);
        assertEq(
            WETH.balanceOf(address(settlement)),
            0.001 ether,
            "settlement contract's weth balance from trade fee not as expected"
        ); // the fee
        assertEq(WETH.balanceOf(trader1.addr), 0, "trader1 weth balance is not 0");
        assertEq(
            trader2.addr.balance, trader2InitialBalance + 1 ether, "trader2 eth balance did not increase as expected"
        );
    }

    function _mintUsdt(address receiver, uint256 amt) internal {
        address owner = USDT.getOwner();
        vm.startPrank(owner);
        USDT.issue(amt);
        USDT.transfer(receiver, amt);
        vm.stopPrank();
    }
}
