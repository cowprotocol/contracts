// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Eip712} from "../libraries/Eip712.sol";
import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";
import {IExchange, ZeroExV2, ZeroExV2Order, ZeroExV2SimpleOrder} from "./ZeroExV2.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

contract ZeroExTradeTest is Helper(false) {
    IERC20Mintable OWL;
    IERC20Mintable GNO;

    Vm.Wallet marketMaker;

    address exchange;
    address erc20Proxy;
    address zrx;

    function setUp() public override {
        super.setUp();

        OWL = deployMintableErc20("OWL", "OWL");
        GNO = deployMintableErc20("GNO", "GNO");

        marketMaker = vm.createWallet("marketMaker");

        (zrx, erc20Proxy, exchange) = ZeroExV2.deployExchange(deployer);
    }

    function test_should_settle_an_eoa_trade_with_a_0x_trade() external {
        // mint some tokens to trader
        OWL.mint(trader.addr, 140 ether);
        vm.prank(trader.addr);
        OWL.approve(vaultRelayer, type(uint256).max);

        // place order to buy 1 OWL with max 130 GNO
        GPv2Order.Data memory makerOrder = GPv2Order.Data({
            kind: GPv2Order.KIND_BUY,
            partiallyFillable: false,
            buyToken: GNO,
            sellToken: OWL,
            buyAmount: 1 ether,
            sellAmount: 130 ether,
            feeAmount: 10 ether,
            validTo: 0xffffffff,
            appData: bytes32(uint256(1)),
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            receiver: GPv2Order.RECEIVER_SAME_AS_OWNER
        });
        encoder.signEncodeTrade(vm, trader, makerOrder, domainSeparator, GPv2Signing.Scheme.Eip712, 0);

        // mint some tokens to market maker
        GNO.mint(marketMaker.addr, 1000 ether);
        vm.prank(marketMaker.addr);
        GNO.approve(erc20Proxy, type(uint256).max);

        // sign zero ex order
        uint256 zeroExGnoPrice = 110;
        (ZeroExV2Order memory order, bytes32 hash, uint8 v, bytes32 r, bytes32 s) = ZeroExV2.signSimpleOrder(
            marketMaker,
            exchange,
            ZeroExV2SimpleOrder({
                takerAddress: address(settlement),
                makerAssetAddress: address(GNO),
                makerAssetAmount: 1000 ether,
                takerAssetAddress: address(OWL),
                takerAssetAmount: 1000 ether * zeroExGnoPrice
            })
        );
        assertTrue(
            IExchange(exchange).isValidSignature(hash, marketMaker.addr, ZeroExV2.encodeSignature(v, r, s)),
            "zero ex v2 order signature is invalid"
        );

        uint256 zeroExTakerAmount = makerOrder.buyAmount * zeroExGnoPrice;

        uint256 gpv2GnoPrice = 120;
        // add interactions for filling the zero ex order in settlement
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(OWL),
                value: 0,
                callData: abi.encodeCall(IERC20.approve, (erc20Proxy, zeroExTakerAmount))
            }),
            SettlementEncoder.InteractionStage.INTRA
        );
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: exchange,
                value: 0,
                callData: abi.encodeCall(IExchange.fillOrder, (order, zeroExTakerAmount, ZeroExV2.encodeSignature(v, r, s)))
            }),
            SettlementEncoder.InteractionStage.INTRA
        );

        // set token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = OWL;
        tokens[1] = GNO;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1;
        prices[1] = gpv2GnoPrice;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        uint256 gpv2OwlSurplus = makerOrder.sellAmount - (makerOrder.buyAmount * gpv2GnoPrice);
        uint256 zeroExOwlSurplus = makerOrder.buyAmount * (gpv2GnoPrice - zeroExGnoPrice);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);
        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(OWL.balanceOf(trader.addr), gpv2OwlSurplus, "trader owl surplus not as expected");
        assertEq(
            OWL.balanceOf(address(settlement)),
            zeroExOwlSurplus + makerOrder.feeAmount,
            "settlement surplus and fee not as expected"
        );
    }

    function _generateSettlementSolution() internal {}
}
