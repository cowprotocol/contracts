// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2VaultRelayer, IVault, IERC20, GPv2Order, GPv2Transfer} from "src/contracts/GPv2VaultRelayer.sol";

contract Helper is Test {
    address payable internal creator = payable(makeAddr("GPv2VaultRelayer.Helper creator"));
    IVault internal vault = IVault(makeAddr("GPv2VaultRelayer.Helper vault"));
    GPv2VaultRelayer internal vaultRelayer;

    function setUp() public {
        // Some calls check if the vault is a contract. `0xfe` is the designated
        // invalid instruction: this way, calling the vault without a mock
        // triggers a revert with `InvalidEFOpcode`.
        vm.etch(address(vault), hex"fe");

        vm.prank(creator);
        vaultRelayer = new GPv2VaultRelayer(vault);
    }
}

contract BatchSwapWithFeeHelper is Helper {
    // All input parameters to `batchSwapWithFee`
    struct SwapWithFees {
        IVault.SwapKind kind;
        IVault.BatchSwapStep[] swaps;
        IERC20[] tokens;
        IVault.FundManagement funds;
        int256[] limits;
        uint256 deadline;
        GPv2Transfer.Data feeTransfer;
    }

    function defaultSwapWithFees() internal pure returns (SwapWithFees memory) {
        return SwapWithFees({
            kind: IVault.SwapKind.GIVEN_IN,
            swaps: new IVault.BatchSwapStep[](0),
            tokens: new IERC20[](0),
            funds: IVault.FundManagement({
                sender: address(0),
                fromInternalBalance: true,
                recipient: payable(address(0)),
                toInternalBalance: true
            }),
            limits: new int256[](0),
            deadline: 0,
            feeTransfer: GPv2Transfer.Data({
                account: address(0),
                token: IERC20(address(0)),
                amount: 0,
                balance: GPv2Order.BALANCE_ERC20
            })
        });
    }

    // Wrapper function to call `batchSwapWithFee` with structured data
    function batchSwapWithFee(GPv2VaultRelayer vaultRelayer, SwapWithFees memory swap)
        internal
        returns (int256[] memory)
    {
        return vaultRelayer.batchSwapWithFee(
            swap.kind, swap.swaps, swap.tokens, swap.funds, swap.limits, swap.deadline, swap.feeTransfer
        );
    }
}
