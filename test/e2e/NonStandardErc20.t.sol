// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {ERC20NoReturn, ERC20ReturningUint} from "../src/NonStandardERC20.sol";
import {Helper} from "./Helper.sol";
import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {GPv2Order, GPv2Signing, SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

contract NonStandardErc20Test is Helper(false) {
    ERC20NoReturn noReturnToken;
    ERC20ReturningUint uintReturningToken;

    function setUp() public override {
        super.setUp();

        noReturnToken = new ERC20NoReturn();
        uintReturningToken = new ERC20ReturningUint();
    }

    function test_should_allow_trading_non_standard_erc20_tokens() external {
        uint256 amount = 1 ether;
        uint256 feeAmount = 0.01 ether;

        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");

        // mint some noReturnToken tokens to trader1
        noReturnToken.mint(trader1.addr, amount + feeAmount);
        vm.prank(trader1.addr);
        noReturnToken.approve(vaultRelayer, type(uint256).max);
        // place order to swap noReturnToken for uintReturningToken
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                sellToken: IERC20(address(noReturnToken)),
                buyToken: IERC20(address(uintReturningToken)),
                receiver: trader1.addr,
                sellAmount: amount,
                buyAmount: amount,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: feeAmount,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // mint some uintReturningToken tokens to trader2
        uintReturningToken.mint(trader2.addr, amount + feeAmount);
        vm.prank(trader2.addr);
        uintReturningToken.approve(vaultRelayer, type(uint256).max);
        // place order to swap uintReturningToken for noReturnToken
        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                sellToken: IERC20(address(uintReturningToken)),
                buyToken: IERC20(address(noReturnToken)),
                receiver: trader2.addr,
                sellAmount: amount,
                buyAmount: amount,
                validTo: 0xffffffff,
                appData: bytes32(uint256(2)),
                feeAmount: feeAmount,
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // set token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(noReturnToken));
        tokens[1] = IERC20(address(uintReturningToken));
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1;
        prices[1] = 1;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        // settle the orders
        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);
        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(noReturnToken.balanceOf(address(settlement)), feeAmount, "order1 fee not charged as expected");
        assertEq(noReturnToken.balanceOf(trader2.addr), amount, "order1 swap output not as expected");

        assertEq(uintReturningToken.balanceOf(address(settlement)), feeAmount, "order2 fee not charged as expected");
        assertEq(uintReturningToken.balanceOf(trader1.addr), amount, "order2 swap output not as expected");
    }
}
