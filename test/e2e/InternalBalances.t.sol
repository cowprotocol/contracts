// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {IVault} from "src/contracts/interfaces/IVault.sol";

import {GPv2Interaction, GPv2Order, GPv2Signing, SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

interface IBalancerVault is IVault {
    function setRelayerApproval(address, address, bool) external;
    function getInternalBalance(address user, IERC20[] memory tokens) external view returns (uint256[] memory);
    function hasApprovedRelayer(address, address) external view returns (bool);
}

contract InternalBalancesTest is Helper(false) {
    IERC20Mintable token1;
    IERC20Mintable token2;

    function setUp() public override {
        super.setUp();

        token1 = deployMintableErc20("TK1", "TK1");
        token2 = deployMintableErc20("TK2", "TK2");

        vm.startPrank(address(settlement));
        token1.approve(address(vault), type(uint256).max);
        token2.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_should_settle_orders_buying_and_selling_with_internal_balances() external {
        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");
        Vm.Wallet memory trader3 = vm.createWallet("trader3");
        Vm.Wallet memory trader4 = vm.createWallet("trader4");

        // mint some tokens to trader1
        _mintTokens(token1, trader1.addr, 1.001 ether);

        // approve tokens to the balancer vault and approve the settlement contract to
        // be able to spend the balancer internal/external balances
        vm.startPrank(trader1.addr);
        token1.approve(address(vault), type(uint256).max);
        IBalancerVault(address(vault)).setRelayerApproval(trader1.addr, vaultRelayer, true);
        vm.stopPrank();

        // place order for selling 1 token1 for 500 token2
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                sellToken: token1,
                buyToken: token2,
                receiver: trader1.addr,
                sellAmount: 1 ether,
                buyAmount: 500 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0.001 ether,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_EXTERNAL,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // mint some tokens to trader2
        _mintTokens(token2, trader2.addr, 300.3 ether);

        // approve tokens to the balancer vault and deposit some tokens to balancer internal
        // balance
        vm.startPrank(trader2.addr);
        token2.approve(address(vault), type(uint256).max);
        IVault.UserBalanceOp[] memory ops = new IVault.UserBalanceOp[](1);
        ops[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token2,
            amount: 300.3 ether,
            sender: trader2.addr,
            recipient: payable(trader2.addr)
        });
        vault.manageUserBalance(ops);
        IBalancerVault(address(vault)).setRelayerApproval(trader2.addr, vaultRelayer, true);
        vm.stopPrank();

        // place order for buying 0.5 token1 with max 300 token2
        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                sellToken: token2,
                buyToken: token1,
                receiver: trader2.addr,
                sellAmount: 300 ether,
                buyAmount: 0.5 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0.3 ether,
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_INTERNAL,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // mint some tokens to trader3
        _mintTokens(token1, trader3.addr, 2.002 ether);

        // approve the tokens to cow vault relayer
        vm.prank(trader3.addr);
        token1.approve(vaultRelayer, type(uint256).max);

        // place order for selling 2 token1 for min 1000 token2
        encoder.signEncodeTrade(
            vm,
            trader3,
            GPv2Order.Data({
                sellToken: token1,
                buyToken: token2,
                receiver: trader3.addr,
                sellAmount: 2 ether,
                buyAmount: 1000 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0.002 ether,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_INTERNAL
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // mint some tokens to trader4
        _mintTokens(token2, trader4.addr, 1501.5 ether);

        // approve tokens to the balancer vault and deposit some tokens to balancer internal
        // balance
        vm.startPrank(trader4.addr);
        token2.approve(address(vault), type(uint256).max);
        ops = new IVault.UserBalanceOp[](1);
        ops[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token2,
            amount: 1501.5 ether,
            sender: trader4.addr,
            recipient: payable(trader4.addr)
        });
        IBalancerVault(address(vault)).manageUserBalance(ops);
        IBalancerVault(address(vault)).setRelayerApproval(trader4.addr, vaultRelayer, true);
        vm.stopPrank();

        // place order to buy 2.5 token1 with max 1500 token2
        encoder.signEncodeTrade(
            vm,
            trader4,
            GPv2Order.Data({
                sellToken: token2,
                buyToken: token1,
                receiver: trader4.addr,
                sellAmount: 1500 ether,
                buyAmount: 2.5 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 1.5 ether,
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_INTERNAL,
                buyTokenBalance: GPv2Order.BALANCE_INTERNAL
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // set token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token1;
        tokens[1] = token2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 550;
        prices[1] = 1;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        // settle the orders
        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);
        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(token2.balanceOf(trader1.addr), 550 ether, "trader1 amountOut not as expected");
        assertEq(token1.balanceOf(trader2.addr), 0.5 ether, "trader2 amountOut not as expected");
        assertEq(_getInternalBalance(address(token2), trader3.addr), 1100 ether, "trader3 amountOut not as expected");
        assertEq(_getInternalBalance(address(token1), trader4.addr), 2.5 ether, "trader4 amountOut not as expected");

        assertEq(token1.balanceOf(address(settlement)), 0.003 ether, "token1 settlement fee amount not as expected");
        assertEq(token2.balanceOf(address(settlement)), 1.8 ether, "token2 settlement fee amount not as expected");
    }

    function _mintTokens(IERC20Mintable token, address to, uint256 amt) internal {
        token.mint(to, amt);
    }

    function _getInternalBalance(address token, address who) internal view returns (uint256) {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(token);
        uint256[] memory bals = IBalancerVault(address(vault)).getInternalBalance(who, tokens);
        return bals[0];
    }
}
