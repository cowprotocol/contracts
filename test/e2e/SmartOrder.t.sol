// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {GPv2Settlement} from "src/contracts/GPv2Settlement.sol";
import {EIP1271Verifier, GPv2EIP1271} from "src/contracts/interfaces/GPv2EIP1271.sol";
import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2SafeERC20} from "src/contracts/libraries/GPv2SafeERC20.sol";
import {SafeMath} from "src/contracts/libraries/SafeMath.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Sign} from "../libraries/Sign.sol";
import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

/// @title Proof of Concept Smart Order
/// @author Gnosis Developers
contract SmartSellOrder is EIP1271Verifier {
    using GPv2Order for GPv2Order.Data;
    using GPv2SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes32 public constant APPDATA = keccak256("SmartSellOrder");

    address public immutable OWNER;
    bytes32 public immutable DOMAIN_SEPARATOR;
    IERC20 public immutable SELL_TOKEN;
    IERC20 public immutable BUY_TOKEN;
    uint256 public immutable TOTAL_SELL_AMOUNT;
    uint256 public immutable TOTAL_FEE_AMOUNT;
    uint32 public immutable VALID_TO;

    constructor(
        GPv2Settlement settlement,
        IERC20 sellToken_,
        IERC20 buyToken_,
        uint32 validTo_,
        uint256 totalSellAmount_,
        uint256 totalFeeAmount_
    ) {
        OWNER = msg.sender;
        DOMAIN_SEPARATOR = settlement.DOMAIN_SEPARATOR();
        SELL_TOKEN = sellToken_;
        BUY_TOKEN = buyToken_;
        VALID_TO = validTo_;
        TOTAL_SELL_AMOUNT = totalSellAmount_;
        TOTAL_FEE_AMOUNT = totalFeeAmount_;

        sellToken_.approve(address(settlement.vaultRelayer()), type(uint256).max);
    }

    modifier onlyOwner() {
        require(msg.sender == OWNER, "not owner");
        _;
    }

    function withdraw(uint256 amount) external onlyOwner {
        SELL_TOKEN.safeTransfer(OWNER, amount);
    }

    function close() external onlyOwner {
        uint256 balance = SELL_TOKEN.balanceOf(address(this));
        if (balance != 0) {
            SELL_TOKEN.safeTransfer(OWNER, balance);
        }
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4 magicValue) {
        uint256 sellAmount = abi.decode(signature, (uint256));
        GPv2Order.Data memory order = orderForSellAmount(sellAmount);

        if (order.hash(DOMAIN_SEPARATOR) == hash) {
            magicValue = GPv2EIP1271.MAGICVALUE;
        }
    }

    function orderForSellAmount(uint256 sellAmount) public view returns (GPv2Order.Data memory order) {
        order.sellToken = SELL_TOKEN;
        order.buyToken = BUY_TOKEN;
        order.receiver = OWNER;
        order.sellAmount = sellAmount;
        order.buyAmount = buyAmountForSellAmount(sellAmount);
        order.validTo = VALID_TO;
        order.appData = APPDATA;
        order.feeAmount = TOTAL_FEE_AMOUNT.mul(sellAmount).div(TOTAL_SELL_AMOUNT);
        order.kind = GPv2Order.KIND_SELL;
        // NOTE: We counter-intuitively set `partiallyFillable` to `false`, even
        // if the smart order as a whole acts like a partially fillable order.
        // This is done since, once a settlement commits to a specific sell
        // amount, then it is expected to use it completely and not partially.
        order.partiallyFillable = false;
        order.sellTokenBalance = GPv2Order.BALANCE_ERC20;
        order.buyTokenBalance = GPv2Order.BALANCE_ERC20;
    }

    function buyAmountForSellAmount(uint256 sellAmount) private view returns (uint256 buyAmount) {
        uint256 feeAdjustedBalance =
            SELL_TOKEN.balanceOf(address(this)).mul(TOTAL_SELL_AMOUNT).div(TOTAL_SELL_AMOUNT.add(TOTAL_FEE_AMOUNT));
        uint256 soldAmount = TOTAL_SELL_AMOUNT > feeAdjustedBalance ? TOTAL_SELL_AMOUNT - feeAdjustedBalance : 0;

        // NOTE: This is currently a silly price strategy where the xrate
        // increases linearly from 1:1 to 1:2 as the smart order gets filled.
        // This can be extended to more complex "price curves".
        buyAmount = sellAmount.mul(TOTAL_SELL_AMOUNT.add(sellAmount).add(soldAmount)).div(TOTAL_SELL_AMOUNT);
    }
}

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
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
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
