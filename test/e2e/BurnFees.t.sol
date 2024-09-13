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

contract BurnFeesTest is Helper(false) {
    IERC20Mintable OWL;
    IERC20Mintable DAI;

    function setUp() public override {
        super.setUp();

        OWL = deployMintableErc20("OWL", "OWL");
        DAI = deployMintableErc20("DAI", "DAI");
    }

    function test_uses_post_interaction_to_burn_settlement_fees() external {
        Vm.Wallet memory trader1 = vm.createWallet("trader1");
        Vm.Wallet memory trader2 = vm.createWallet("trader2");

        // mint some OWL to trader1
        OWL.mint(trader1.addr, 1001 ether);
        vm.prank(trader1.addr);
        // approve OWL for trading on settlement contract
        OWL.approve(vaultRelayer, type(uint256).max);
        // place order to sell 1000 OWL for min 1000 DAI
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellToken: OWL,
                buyToken: DAI,
                sellAmount: 1000 ether,
                buyAmount: 1000 ether,
                feeAmount: 1 ether,
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

        // mint some DAI to trader2
        DAI.mint(trader2.addr, 1000 ether);
        vm.prank(trader2.addr);
        // approve DAI for trading on settlement contract
        DAI.approve(vaultRelayer, type(uint256).max);
        // place order to BUY 1000 OWL with max 1000 DAI
        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellToken: DAI,
                buyToken: OWL,
                sellAmount: 1000 ether,
                buyAmount: 1000 ether,
                feeAmount: 0,
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

        // add post interaction to burn OWL fees
        encoder.addInteraction(
            GPv2Interaction.Data({target: address(OWL), value: 0, callData: abi.encodeCall(OWL.burn, (1 ether))}),
            SettlementEncoder.InteractionStage.POST
        );

        // set the token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = OWL;
        tokens[1] = DAI;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1;
        prices[1] = 1;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);
        vm.prank(solver);
        vm.expectEmit();
        emit IERC20.Transfer(address(settlement), address(0), 1 ether);
        settle(encodedSettlement);

        assertEq(DAI.balanceOf(address(settlement)), 0, "dai balance of settlement contract not 0");
    }
}
