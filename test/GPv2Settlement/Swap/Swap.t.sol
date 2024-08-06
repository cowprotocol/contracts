// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {GPv2Order, GPv2Settlement, GPv2Signing, IERC20, IVault} from "src/contracts/GPv2Settlement.sol";

import {Helper} from "../Helper.sol";
import {Order} from "test/libraries/Order.sol";
import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";

contract Swap is Helper {
    using SwapEncoder for SwapEncoder.State;

    IERC20 private alwaysSuccessfulToken1 = IERC20(makeAddr("GPv2Settlement.Swap always successful token 1"));
    IERC20 private alwaysSuccessfulToken2 = IERC20(makeAddr("GPv2Settlement.Swap always successful token 2"));
    Vm.Wallet private trader1 = vm.createWallet("GPv2Settlement.Swap: trader1");
    Vm.Wallet private trader2 = vm.createWallet("GPv2Settlement.Swap: trader2");

    function emptySwap() private returns (SwapEncoder.EncodedSwap memory) {
        GPv2Order.Data memory order = Order.emptySell();
        order.sellToken = alwaysSuccessfulToken1;
        order.buyToken = alwaysSuccessfulToken2;

        SwapEncoder.State storage swapEncoder = SwapEncoder.makeSwapEncoder();

        swapEncoder.signEncodeTrade({
            vm: vm,
            owner: trader,
            order: order,
            domainSeparator: domainSeparator,
            signingScheme: GPv2Signing.Scheme.Eip712,
            executedAmount: 0
        });
        return swapEncoder.encode();
    }

    function mockSuccess(IERC20 token) private {
        vm.mockCall(address(token), abi.encodePacked(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(address(token), abi.encodePacked(IERC20.transferFrom.selector), abi.encode(true));
    }

    function setUp() public override {
        super.setUp();
        mockSuccess(alwaysSuccessfulToken1);
        mockSuccess(alwaysSuccessfulToken2);
    }

    function test_reverts_if_called_by_non_solver() public {
        vm.expectRevert("GPv2: not a solver");
        swap(emptySwap());
    }

    function test_executes_swap_and_fee_transfer_with_correct_amounts() public {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(makeAddr("sell token")),
            buyToken: IERC20(makeAddr("buy token")),
            receiver: trader2.addr,
            sellAmount: 4.2 ether,
            buyAmount: 13.37 ether,
            validTo: 0x01020304,
            appData: bytes32(0),
            feeAmount: 1 ether,
            kind: GPv2Order.KIND_BUY,
            sellTokenBalance: GPv2Order.BALANCE_INTERNAL,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            partiallyFillable: false
        });

        SwapEncoder.State storage swapEncoder = SwapEncoder.makeSwapEncoder();

        IERC20 intermediateToken1 = IERC20(makeAddr("intermediate token 1"));
        IERC20 intermediateToken2 = IERC20(makeAddr("intermediate token 2"));
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: keccak256("pool id step 1"),
                assetIn: order.sellToken,
                assetOut: intermediateToken1,
                amount: 42 ether,
                userData: bytes("data step 1")
            })
        );
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: keccak256("pool id step 2"),
                assetIn: intermediateToken1,
                assetOut: intermediateToken2,
                amount: 1337 ether,
                userData: bytes("data step 2")
            })
        );
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: keccak256("pool id step 3"),
                assetIn: intermediateToken2,
                assetOut: order.buyToken,
                amount: 6 ether,
                userData: bytes("data step 3")
            })
        );

        swapEncoder.signEncodeTrade({
            vm: vm,
            owner: trader1,
            order: order,
            domainSeparator: domainSeparator,
            signingScheme: GPv2Signing.Scheme.Eip712,
            executedAmount: 0
        });

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: trader1.addr,
            fromInternalBalance: true,
            recipient: payable(trader2.addr),
            toInternalBalance: false
        });
        int256[] memory limits = new int256[](4);
        limits[0] = int256(order.sellAmount);
        limits[1] = 0;
        limits[2] = 0;
        limits[3] = -int256(order.buyAmount);
        int256[] memory output = new int256[](4);
        output[0] = int256(order.sellAmount) / 2;
        output[1] = 0;
        output[2] = 0;
        output[3] = -int256(order.buyAmount);
        vm.mockCall(
            address(vault),
            abi.encodeCall(
                IVault.batchSwap,
                (IVault.SwapKind.GIVEN_OUT, encodedSwap.swaps, encodedSwap.tokens, funds, limits, order.validTo)
            ),
            abi.encode(output)
        );
        IVault.UserBalanceOp[] memory vaultOps = new IVault.UserBalanceOp[](1);
        vaultOps[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.TRANSFER_INTERNAL,
            asset: order.sellToken,
            amount: order.feeAmount,
            sender: trader1.addr,
            recipient: payable(address(settlement))
        });
        vm.mockCall(address(vault), abi.encodeCall(IVault.manageUserBalance, (vaultOps)), hex"");

        vm.prank(solver);
        swap(swapEncoder.encode());
    }

    function test_should_emit_a_settlement_event() public {
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(new int256[](2)));
        vm.mockCall(address(vault), abi.encodePacked(IVault.manageUserBalance.selector), hex"");

        vm.expectEmit(address(settlement));
        emit GPv2Settlement.Settlement(solver);
        vm.prank(solver);
        swap(emptySwap());
    }

    function test_reverts_on_negative_sell_amounts() public {
        int256[] memory output = new int256[](2);
        output[0] = -1;
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(output));
        vm.mockCall(address(vault), abi.encodePacked(IVault.manageUserBalance.selector), hex"");

        vm.expectRevert("SafeCast: not positive");
        vm.prank(solver);
        swap(emptySwap());
    }

    function test_reverts_on_positive_buy_amounts() public {
        int256[] memory output = new int256[](2);
        output[1] = 1;
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(output));
        vm.mockCall(address(vault), abi.encodePacked(IVault.manageUserBalance.selector), hex"");

        vm.expectRevert("SafeCast: not positive");
        vm.prank(solver);
        swap(emptySwap());
    }

    function test_reverts_on_unary_negation_overflow_for_buy_amounts() public {
        int256[] memory output = new int256[](2);
        output[1] = type(int256).min;
        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(output));
        vm.mockCall(address(vault), abi.encodePacked(IVault.manageUserBalance.selector), hex"");

        // NOTE: this test used to revert with "SafeCast: not positive".
        // However, we are running these tests in Solidity v8, which causes
        // all overflows to panic before `SafeCast` can catch them.
        // NOTE: this just asserts that the call reverts. As of now it doesn't
        // seem to be possible to just assert that the message is empty.
        // TODO: once Foundry supports catching EVM errors, require that this
        // reverts with "arithmetic underflow or overflow".
        // Track support at https://github.com/foundry-rs/foundry/issues/4012
        vm.expectRevert();
        vm.prank(solver);
        swap(emptySwap());
    }
}
