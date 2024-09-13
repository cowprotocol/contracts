// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Sign} from "../libraries/Sign.sol";
import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {SmartSellOrder} from "../src/SmartSellOrder.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

contract SmartOrderTest is Helper(false) {
    IERC20Mintable token1;
    IERC20Mintable token2;

    function setUp() public override {
        super.setUp();

        token1 = deployMintableErc20("TK1", "TK1");
        token2 = deployMintableErc20("TK2", "TK2");
    }

    function test_permits_trader_allowance_with_settlement() external {
        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");

        // mint some tokens
        token1.mint(trader1.addr, 1.01 ether);
        vm.prank(trader1.addr);
        // approve tokens to vault relayer
        token1.approve(vaultRelayer, type(uint256).max);
        // place order to buy 0.5 token2 with 1 token1 max
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellToken: token1,
                buyToken: token2,
                sellAmount: 1 ether,
                buyAmount: 0.5 ether,
                feeAmount: 0.01 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20,
                receiver: GPv2Order.RECEIVER_SAME_AS_OWNER
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        vm.prank(trader2.addr);
        SmartSellOrder smartOrder = new SmartSellOrder(settlement, token2, token1, 0xffffffff, 1 ether, 0.1 ether);
        token2.mint(trader2.addr, 1.1 ether);
        vm.prank(trader2.addr);
        token2.transfer(address(smartOrder), 1.1 ether);

        uint256 smartOrderSellAmount = 0.5 ether;
        GPv2Order.Data memory smartOrderTrade = smartOrder.orderForSellAmount(smartOrderSellAmount);
        GPv2Order.Data memory expectedOrder = GPv2Order.Data({
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellToken: token2,
            buyToken: token1,
            receiver: trader2.addr,
            sellAmount: smartOrderSellAmount,
            buyAmount: 0.75 ether,
            feeAmount: 0.05 ether,
            validTo: 0xffffffff,
            appData: smartOrder.APPDATA(),
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        assertEq(
            keccak256(abi.encode(smartOrderTrade)), keccak256(abi.encode(expectedOrder)), "smart order not as expected"
        );

        encoder.encodeTrade(
            smartOrderTrade,
            Sign.Signature({
                scheme: GPv2Signing.Scheme.Eip1271,
                data: abi.encodePacked(address(smartOrder), abi.encode(smartOrderSellAmount))
            }),
            0
        );

        // set token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token1;
        tokens[1] = token2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 10;
        prices[1] = 15;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);

        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(token1.balanceOf(trader2.addr), 0.75 ether);
    }
}
