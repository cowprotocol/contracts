// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {IVault} from "src/contracts/interfaces/IVault.sol";

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {SwapEncoder} from "../libraries/encoders/SwapEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;
using SwapEncoder for SwapEncoder.State;

interface IMockPool {
    function registerTokens(IERC20[] calldata tokens, address[] calldata assetManagers) external;
    function getPoolId() external view returns (bytes32);
    function setMultiplier(uint256) external;
}

interface IBalancerVault is IVault {
    struct JoinPoolRequest {
        IERC20[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest calldata request) external;
    function setRelayerApproval(address, address, bool) external;
    function getInternalBalance(address user, IERC20[] calldata tokens) external view returns (uint256[] memory);
}

contract BalancerSwapTest is Helper(false) {
    IERC20Mintable token1;
    IERC20Mintable token2;
    IERC20Mintable token3;

    mapping(address => mapping(address => address)) pools;

    function setUp() public override {
        super.setUp();

        token1 = deployMintableErc20("TOK1", "TOK1");
        token2 = deployMintableErc20("TOK2", "TOK2");
        token3 = deployMintableErc20("TOK3", "TOK3");

        Vm.Wallet memory pooler = vm.createWallet("pooler");

        IERC20Mintable[] memory tokens = new IERC20Mintable[](3);
        tokens[0] = token1;
        tokens[1] = token2;
        tokens[2] = token3;

        uint256 lots = 10000 ether;

        for (uint256 i = 0; i < tokens.length; i++) {
            (IERC20Mintable token0_, IERC20Mintable token1_) = (tokens[i], tokens[(i + 1) % tokens.length]);
            (IERC20Mintable tokenA, IERC20Mintable tokenB) =
                address(token0_) < address(token1_) ? (token0_, token1_) : (token1_, token0_);

            uint256 twoTokenSpecialization = 2;

            vm.startPrank(deployer);
            IMockPool pool = IMockPool(
                _create(
                    abi.encodePacked(
                        vm.getCode("balancer/test/MockPool.json"), abi.encode(address(vault), twoTokenSpecialization)
                    ),
                    0
                )
            );
            IERC20[] memory tks = new IERC20[](2);
            tks[0] = tokenA;
            tks[1] = tokenB;
            address[] memory assetManagers = new address[](2);
            assetManagers[0] = address(0);
            assetManagers[1] = address(0);
            pool.registerTokens(tks, assetManagers);
            vm.stopPrank();

            for (uint256 j = 0; j < tks.length; j++) {
                IERC20Mintable(address(tks[j])).mint(pooler.addr, lots);
                vm.prank(pooler.addr);
                tks[j].approve(address(vault), type(uint256).max);
            }

            uint256[] memory maxAmountsIn = new uint256[](2);
            maxAmountsIn[0] = lots;
            maxAmountsIn[1] = lots;
            uint256[] memory poolFees = new uint256[](2);
            IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
                assets: tks,
                maxAmountsIn: maxAmountsIn,
                // NOTE: The mock pool uses this for encoding the pool share amounts
                // that a user (here `pooler`) gets when joining the pool (first value)
                // as well as the pool fees (second value).
                userData: abi.encode(maxAmountsIn, poolFees),
                fromInternalBalance: false
            });
            address poolerAddr = pooler.addr;
            bytes32 poolId = pool.getPoolId();
            vm.prank(poolerAddr);
            IBalancerVault(address(vault)).joinPool(poolId, poolerAddr, poolerAddr, request);

            pools[address(tokenA)][address(tokenB)] = address(pool);
            pools[address(tokenB)][address(tokenA)] = address(pool);
        }
    }

    function test_reverts_if_order_is_expired() external {
        _mintAndApprove(trader, token1, 100.1 ether, GPv2Order.BALANCE_ERC20);

        swapEncoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellToken: token1,
                buyToken: token2,
                sellAmount: 100 ether,
                buyAmount: 72 ether,
                feeAmount: 0.1 ether,
                validTo: uint32(block.timestamp) - 1,
                appData: bytes32(uint256(1)),
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20,
                receiver: GPv2Order.RECEIVER_SAME_AS_OWNER
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();
        vm.prank(solver);
        // SWAP_DEADLINE
        vm.expectRevert("BAL#508");
        swap(encodedSwap);
    }

    function test_allows_using_liquidity_from_multiple_pools() external {
        _mintAndApprove(trader, token1, 100.1 ether, GPv2Order.BALANCE_ERC20);

        swapEncoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellToken: token1,
                buyToken: token3,
                sellAmount: 100 ether,
                buyAmount: 125 ether,
                feeAmount: 0.1 ether,
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

        // NOTE: Use liquidity by performing a multi-hop swap from `0 -> 1 -> 2`.
        _poolFor(token1, token2).setMultiplier(1.1 ether);
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: _poolFor(token1, token2).getPoolId(),
                assetIn: token1,
                assetOut: token2,
                amount: 70 ether,
                userData: hex""
            })
        );
        _poolFor(token2, token3).setMultiplier(1.2 ether);
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: _poolFor(token2, token3).getPoolId(),
                assetIn: token2,
                assetOut: token3,
                // NOTE: Setting amount to zero indicates a "multi-hop" swap and uses the
                // computed `amountOut` of the previous swap.
                amount: 0,
                userData: hex""
            })
        );
        // NOTE: Also use liquidity from a direct `0 -> 2` pool.
        _poolFor(token1, token3).setMultiplier(1.3 ether);
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: _poolFor(token1, token3).getPoolId(),
                assetIn: token1,
                assetOut: token3,
                amount: 30 ether,
                userData: hex""
            })
        );

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();
        vm.prank(solver);
        swap(encodedSwap);

        // NOTE: Sold 70 for 1.1*1.2 and 30 for 1.3, so should receive 131.4.
        assertEq(
            _balanceOf(trader.addr, token3, GPv2Order.BALANCE_ERC20),
            131.4 ether,
            "multihop swap output not as expected"
        );
    }

    function test_allows_multi_hop_buy_orders() external {
        _mintAndApprove(trader, token1, 13.1 ether, GPv2Order.BALANCE_ERC20);

        swapEncoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellToken: token1,
                buyToken: token3,
                sellAmount: 13 ether,
                buyAmount: 100 ether,
                feeAmount: 0.1 ether,
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

        // NOTE: Use liquidity by performing a multi-hop swap from `2 -> 1 -> 0`.
        _poolFor(token3, token2).setMultiplier(4 ether);
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: _poolFor(token3, token2).getPoolId(),
                assetOut: token3,
                assetIn: token2,
                amount: 100 ether,
                userData: hex""
            })
        );
        _poolFor(token2, token1).setMultiplier(2 ether);
        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: _poolFor(token2, token1).getPoolId(),
                assetOut: token2,
                assetIn: token1,
                // NOTE: Setting amount to zero indicates a "multi-hop" swap and uses the
                // computed `amountIn` of the previous swap.
                amount: 0,
                userData: hex""
            })
        );

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();
        vm.prank(solver);
        swap(encodedSwap);

        // NOTE: Bought 100 for 4.0*2.0, so should pay 12.5.
        assertEq(
            _balanceOf(trader.addr, token1, GPv2Order.BALANCE_ERC20), 0.5 ether, "multihop swap output not as expected"
        );
    }

    function test_performs_balancer_swap_for_erc20_to_erc20_sell_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_ERC20, GPv2Order.KIND_SELL);
    }

    function test_performs_balancer_swap_for_erc20_to_internal_sell_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_INTERNAL, GPv2Order.KIND_SELL);
    }

    function test_performs_balancer_swap_for_internal_to_erc20_sell_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_INTERNAL, GPv2Order.BALANCE_ERC20, GPv2Order.KIND_SELL);
    }

    function test_performs_balancer_swap_for_internal_to_internal_sell_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_INTERNAL, GPv2Order.BALANCE_INTERNAL, GPv2Order.KIND_SELL);
    }

    function test_performs_balancer_swap_for_external_to_erc20_sell_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_ERC20, GPv2Order.KIND_SELL);
    }

    function test_performs_balancer_swap_for_external_to_internal_sell_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_INTERNAL, GPv2Order.KIND_SELL);
    }

    function test_performs_balancer_swap_for_erc20_to_erc20_buy_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_ERC20, GPv2Order.KIND_BUY);
    }

    function test_performs_balancer_swap_for_erc20_to_internal_buy_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_ERC20, GPv2Order.BALANCE_INTERNAL, GPv2Order.KIND_BUY);
    }

    function test_performs_balancer_swap_for_internal_to_erc20_buy_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_INTERNAL, GPv2Order.BALANCE_ERC20, GPv2Order.KIND_BUY);
    }

    function test_performs_balancer_swap_for_internal_to_internal_buy_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_INTERNAL, GPv2Order.BALANCE_INTERNAL, GPv2Order.KIND_BUY);
    }

    function test_performs_balancer_swap_for_external_to_erc20_buy_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_ERC20, GPv2Order.KIND_BUY);
    }

    function test_performs_balancer_swap_for_external_to_internal_buy_order() external {
        _testBalancerSwap(GPv2Order.BALANCE_EXTERNAL, GPv2Order.BALANCE_INTERNAL, GPv2Order.KIND_BUY);
    }

    function test_reverts_sell_order_if_fill_or_kill_is_not_respected() external {
        _testBalancerRevertFillOrKill(GPv2Order.KIND_SELL);
    }

    function test_reverts_buy_order_if_fill_or_kill_is_not_respected() external {
        _testBalancerRevertFillOrKill(GPv2Order.KIND_BUY);
    }

    function test_reverts_sell_order_if_limit_price_is_not_respected() external {
        _testBalancerRevertLimitPrice(GPv2Order.KIND_SELL);
    }

    function test_reverts_buy_order_if_limit_price_is_not_respected() external {
        _testBalancerRevertLimitPrice(GPv2Order.KIND_BUY);
    }

    function _testBalancerSwap(bytes32 sellSource, bytes32 buySource, bytes32 orderKind) internal {
        _mintAndApprove(trader, token1, 100.1 ether, sellSource);

        IMockPool pool = _poolFor(token1, token2);
        // NOTE: Set a fixed multiplier used for computing the exchange rate for
        // the mock pool. In the wild, this would depend on the current state of
        // the pool.
        pool.setMultiplier(0.9 ether);

        swapEncoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: orderKind,
                partiallyFillable: false,
                sellToken: token1,
                buyToken: token2,
                sellAmount: 100 ether,
                buyAmount: 72 ether,
                feeAmount: 0.1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                sellTokenBalance: sellSource,
                buyTokenBalance: buySource,
                receiver: GPv2Order.RECEIVER_SAME_AS_OWNER
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: pool.getPoolId(),
                assetIn: token1,
                assetOut: token2,
                amount: orderKind == GPv2Order.KIND_SELL ? 100 ether : 72 ether,
                userData: hex""
            })
        );

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();

        vm.prank(solver);
        swap(encodedSwap);

        uint256 sellTokenBalance = _balanceOf(trader.addr, token1, sellSource);
        uint256 buyTokenBalance = _balanceOf(trader.addr, token2, buySource);

        if (orderKind == GPv2Order.KIND_SELL) {
            assertEq(sellTokenBalance, 0, "seller sellTokenBalance not as expected");
            assertEq(buyTokenBalance, 90 ether, "seller buyTokenBalance not as expected");
        } else {
            assertEq(sellTokenBalance, 20 ether, "buyer sellTokenBalance not as expected");
            assertEq(buyTokenBalance, 72 ether, "buyer buyTokenBalance not as expected");
        }
    }

    function _testBalancerRevertFillOrKill(bytes32 orderKind) internal {
        _mintAndApprove(trader, token1, 100.1 ether, GPv2Order.BALANCE_ERC20);

        IMockPool pool = _poolFor(token1, token2);
        pool.setMultiplier(2 ether);

        swapEncoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: orderKind,
                // NOTE: Partially fillable or not, it doesn't matter as the
                // "fast-path" treats all orders as fill-or-kill orders.
                partiallyFillable: true,
                sellToken: token1,
                buyToken: token2,
                sellAmount: 100 ether,
                buyAmount: 100 ether,
                feeAmount: 0.1 ether,
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

        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: pool.getPoolId(),
                assetIn: token1,
                assetOut: token2,
                amount: orderKind == GPv2Order.KIND_SELL ? 99 ether : 101 ether,
                userData: hex""
            })
        );

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();

        vm.expectRevert(
            bytes(
                orderKind == GPv2Order.KIND_SELL ? "GPv2: sell amount not respected" : "GPv2: buy amount not respected"
            )
        );
        vm.prank(solver);
        swap(encodedSwap);
    }

    function _testBalancerRevertLimitPrice(bytes32 orderKind) internal {
        _mintAndApprove(trader, token1, 100.1 ether, GPv2Order.BALANCE_ERC20);

        IMockPool pool = _poolFor(token1, token2);
        // NOTE: Set a multiplier that satisfies the order's limit price but not
        // the specified limit amount.
        pool.setMultiplier(1.1 ether);

        swapEncoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: orderKind,
                partiallyFillable: false,
                sellToken: token1,
                buyToken: token2,
                sellAmount: 100 ether,
                buyAmount: 100 ether,
                feeAmount: 0.1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20,
                receiver: GPv2Order.RECEIVER_SAME_AS_OWNER
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            orderKind == GPv2Order.KIND_SELL ? 120 ether : 80 ether
        );

        swapEncoder.encodeSwapStep(
            SwapEncoder.Swap({
                poolId: pool.getPoolId(),
                assetIn: token1,
                assetOut: token2,
                amount: 100 ether,
                userData: hex""
            })
        );

        SwapEncoder.EncodedSwap memory encodedSwap = swapEncoder.encode();

        vm.expectRevert("BAL#507");
        vm.prank(solver);
        swap(encodedSwap);
    }

    function _mintAndApprove(Vm.Wallet memory wallet, IERC20Mintable token, uint256 amount, bytes32 balance) internal {
        token.mint(wallet.addr, amount);
        vm.startPrank(wallet.addr);
        token.approve(vaultRelayer, type(uint256).max);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        if (balance == GPv2Order.BALANCE_INTERNAL) {
            vm.prank(wallet.addr);
            IVault.UserBalanceOp[] memory ops = new IVault.UserBalanceOp[](1);
            ops[0] = IVault.UserBalanceOp({
                kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
                asset: token,
                amount: amount,
                sender: wallet.addr,
                recipient: payable(wallet.addr)
            });
            vault.manageUserBalance(ops);
        }
        vm.prank(wallet.addr);
        IBalancerVault(address(vault)).setRelayerApproval(wallet.addr, vaultRelayer, true);
    }

    function _poolFor(IERC20 tk0, IERC20 tk1) internal view returns (IMockPool) {
        return IMockPool(pools[address(tk0)][address(tk1)]);
    }

    function _balanceOf(address user, IERC20 tk, bytes32 balance) internal view returns (uint256) {
        if (balance == GPv2Order.BALANCE_INTERNAL) {
            IERC20[] memory tks = new IERC20[](1);
            tks[0] = tk;
            uint256[] memory bals = IBalancerVault(address(vault)).getInternalBalance(user, tks);
            return bals[0];
        } else {
            return tk.balanceOf(user);
        }
    }
}
