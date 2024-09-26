// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

interface IUniswapV2Factory {
    function createPair(address, address) external returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function mint(address) external;
    function swap(uint256, uint256, address, bytes calldata) external;
}

contract UniswapTradeTest is Helper(true) {
    IERC20Mintable dai;
    IERC20Mintable wETH;

    IUniswapV2Factory factory;
    IUniswapV2Pair uniswapPair;

    bool isWethToken0;

    function setUp() public override {
        super.setUp();

        dai = deployMintableErc20("dai", "dai");
        wETH = deployMintableErc20("wETH", "wETH");

        factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        uniswapPair = IUniswapV2Pair(factory.createPair(address(wETH), address(dai)));

        isWethToken0 = uniswapPair.token0() == address(wETH);
    }

    // Settles the following batch:
    //
    //   /----(1. SELL 1 wETH for dai if p(wETH) >= 500)-----\
    //   |                                                    |
    //   |                                                    v
    // [dai]<---(Uniswap Pair 1000 wETH / 600.000 dai)--->[wETH]
    //   ^                                                    |
    //   |                                                    |
    //   \----(2. BUY 0.5 wETH for dai if p(wETH) <= 600)----/
    function test_should_two_overlapping_orders_and_trade_surplus_with_uniswap() external {
        uint256 wethReserve = 1000 ether;
        uint256 daiReserve = 600000 ether;
        wETH.mint(address(uniswapPair), wethReserve);
        dai.mint(address(uniswapPair), daiReserve);
        uniswapPair.mint(address(this));

        // The current batch has a sell order selling 1 wETH and a buy order buying
        // 0.5 wETH. This means there is exactly a surplus 0.5 wETH that needs to be
        // sold to Uniswap. Uniswap is governed by a balancing equation which can be
        // used to compute the exact buy amount for selling the 0.5 wETH and we can
        // use to build our the settlement with a smart contract interaction.
        // ```
        // (reservewETH + inwETH * 0.997) * (reservedai - outdai) = reservewETH * reservedai
        // outdai = (reservedai * inwETH * 0.997) / (reservewETH + inwETH * 0.997)
        //         = (reservedai * inwETH * 997) / (reservewETH * 1000 + inwETH * 997)
        // ```
        uint256 uniswapWethInAmount = 0.5 ether;
        uint256 uniswapDaiOutAmount =
            daiReserve * uniswapWethInAmount * 997 / ((wethReserve * 1000) + (uniswapWethInAmount * 997));

        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");

        // mint some weth
        wETH.mint(trader1.addr, 1.001 ether);
        vm.prank(trader1.addr);
        wETH.approve(vaultRelayer, type(uint256).max);

        // place order to sell 1 wETH for min 500 dai
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellToken: wETH,
                buyToken: dai,
                sellAmount: 1 ether,
                buyAmount: 500 ether,
                feeAmount: 0.001 ether,
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

        // mint some dai
        dai.mint(trader2.addr, 300.3 ether);
        vm.prank(trader2.addr);
        dai.approve(vaultRelayer, type(uint256).max);

        // place order to buy 0.5 wETH for max 300 dai
        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellToken: dai,
                buyToken: wETH,
                sellAmount: 300 ether,
                buyAmount: 0.5 ether,
                feeAmount: 0.3 ether,
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

        // interaction to swap the remainder on uniswap
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(wETH),
                value: 0,
                callData: abi.encodeCall(IERC20.transfer, (address(uniswapPair), uniswapWethInAmount))
            }),
            SettlementEncoder.InteractionStage.INTRA
        );
        (uint256 amount0Out, uint256 amount1Out) =
            isWethToken0 ? (uint256(0), uniswapDaiOutAmount) : (uniswapDaiOutAmount, uint256(0));
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(uniswapPair),
                value: 0,
                callData: abi.encodeCall(IUniswapV2Pair.swap, (amount0Out, amount1Out, address(settlement), hex""))
            }),
            SettlementEncoder.InteractionStage.INTRA
        );

        // set token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = wETH;
        tokens[1] = dai;
        uint256[] memory prices = new uint256[](2);
        prices[0] = uniswapDaiOutAmount;
        prices[1] = uniswapWethInAmount;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);

        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(wETH.balanceOf(address(settlement)), 0.001 ether, "weth fees not as expected");
        assertEq(dai.balanceOf(address(settlement)), 0.3 ether, "dai fees not as expected");

        assertEq(wETH.balanceOf(trader1.addr), 0, "not all weth sold");
        assertEq(dai.balanceOf(trader1.addr), uniswapDaiOutAmount * 2, "dai received not as expected");

        assertEq(wETH.balanceOf(trader2.addr), 0.5 ether, "weth bought not correct amount");
        assertEq(dai.balanceOf(trader2.addr), 300.3 ether - (uniswapDaiOutAmount + 0.3 ether));
    }

    function _getCode(string memory artifactName) internal view returns (bytes memory) {
        string memory data =
            vm.readFile(string(abi.encodePacked("node_modules/@uniswap/v2-core/build/", artifactName, ".json")));
        return vm.parseJsonBytes(data, ".bytecode");
    }
}
