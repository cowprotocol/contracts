// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {
    GPv2VaultRelayer, GPv2Transfer, IERC20, IVault, GPv2Transfer, GPv2Order
} from "src/contracts/GPv2VaultRelayer.sol";

import {BatchSwapWithFeeHelper} from "./Helper.sol";

contract BatchSwapWithFee is BatchSwapWithFeeHelper {
    function test_should_revert_if_not_called_by_the_creator() public {
        vm.prank(makeAddr("not the creator"));
        vm.expectRevert("GPv2: not creator");
        batchSwapWithFee(vaultRelayer, defaultSwapWithFees());
    }

    function test_performs_swaps_given_in() public {
        performs_swaps_for_swap_kind(IVault.SwapKind.GIVEN_IN);
    }

    function test_performs_swaps_given_out() public {
        performs_swaps_for_swap_kind(IVault.SwapKind.GIVEN_OUT);
    }

    function performs_swaps_for_swap_kind(IVault.SwapKind kind) private {
        address trader0 = makeAddr("trader 0");
        address trader1 = makeAddr("trader 1");

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);
        swaps[0] = IVault.BatchSwapStep({
            poolId: keccak256("pool id 1"),
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: 42 ether,
            userData: hex"010203"
        });
        swaps[1] = IVault.BatchSwapStep({
            poolId: keccak256("pool id 2"),
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 1337 ether,
            userData: hex"abcd"
        });

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(makeAddr("token 0"));
        tokens[1] = IERC20(makeAddr("token 1"));
        tokens[2] = IERC20(makeAddr("token 2"));

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: trader0,
            fromInternalBalance: false,
            recipient: payable(trader1),
            toInternalBalance: true
        });

        int256[] memory limits = new int256[](3);
        limits[0] = 42 ether;
        limits[1] = 0;
        limits[2] = -1337 ether;

        uint256 deadline = 0x01020304;

        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader0, token: tokens[0], amount: 1 ether, balance: GPv2Order.BALANCE_ERC20});

        // end parameter setup

        vm.mockCall(
            address(vault),
            abi.encodeCall(IVault.batchSwap, (kind, swaps, tokens, funds, limits, deadline)),
            abi.encode(new int256[](0))
        );
        // Note: any transfer should return true.
        vm.mockCall(address(tokens[0]), abi.encodePacked(IERC20.transferFrom.selector), abi.encode(true));

        vm.prank(creator);
        batchSwapWithFee(
            vaultRelayer,
            SwapWithFees({
                kind: kind,
                swaps: swaps,
                tokens: tokens,
                funds: funds,
                limits: limits,
                deadline: deadline,
                feeTransfer: feeTransfer
            })
        );
    }

    function test_returns_the_vault_swap_token_delta() public {
        address trader = makeAddr("trader");

        int256[] memory deltas = new int256[](3);
        deltas[0] = 42 ether;
        deltas[1] = 0;
        deltas[2] = -1337 ether;

        IERC20 token = IERC20(makeAddr("token"));
        GPv2Transfer.Data memory feeTransfer =
            GPv2Transfer.Data({account: trader, token: token, amount: 1 ether, balance: GPv2Order.BALANCE_ERC20});

        vm.mockCall(address(vault), abi.encodePacked(IVault.batchSwap.selector), abi.encode(deltas));
        // Note: vault relayer checks that the token is a contract. "fe" causes
        // a revert on any function that isn't mocked.
        vm.etch(address(token), hex"fe");
        vm.mockCall(address(token), abi.encodePacked(IERC20.transferFrom.selector), abi.encode(true));

        SwapWithFees memory swapWithFees = defaultSwapWithFees();
        swapWithFees.kind = IVault.SwapKind.GIVEN_IN;
        swapWithFees.feeTransfer = feeTransfer;

        vm.prank(creator);
        int256[] memory result = batchSwapWithFee(vaultRelayer, swapWithFees);
        assertEq(result, deltas);
    }

    function test_reverts_on_failed_vault_swap() public {
        vm.mockCallRevert(address(vault), abi.encodePacked(IVault.batchSwap.selector), "mock revert");
        vm.prank(creator);
        vm.expectRevert("mock revert");
        batchSwapWithFee(vaultRelayer, defaultSwapWithFees());
    }
}
