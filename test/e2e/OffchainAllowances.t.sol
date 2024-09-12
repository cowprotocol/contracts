// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {IVault} from "src/contracts/interfaces/IVault.sol";
import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Eip712} from "../libraries/Eip712.sol";
import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

interface IERC2612 {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface IBalancerVault {
    function getDomainSeparator() external view returns (bytes32);
    function setRelayerApproval(address, address, bool) external;
}

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

contract OffchainAllowancesTest is Helper(false) {
    IERC20Mintable EUR1;
    IERC20Mintable EUR2;

    Vm.Wallet trader1;
    Vm.Wallet trader2;

    function setUp() public override {
        super.setUp();

        EUR1 = IERC20Mintable(_create(abi.encodePacked(vm.getCode("ERC20PresetPermit"), abi.encode("EUR1")), 0));
        EUR2 = IERC20Mintable(_create(abi.encodePacked(vm.getCode("ERC20PresetPermit"), abi.encode("EUR1")), 0));

        trader1 = vm.createWallet("trader1");
        trader2 = vm.createWallet("trader2");
    }

    function test_eip_2612_permits_trader_allowance_with_settlement() external {
        // mint and approve tokens to and from trader1
        EUR1.mint(trader1.addr, 1 ether);
        vm.prank(trader1.addr);
        EUR1.approve(vaultRelayer, type(uint256).max);

        // place order to sell 1 EUR1 for min 1 EUR2 from trader1
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                sellToken: EUR1,
                buyToken: EUR2,
                receiver: trader1.addr,
                sellAmount: 1 ether,
                buyAmount: 1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // mint some tokens to trader2
        EUR2.mint(trader2.addr, 1 ether);
        uint256 nonce = IERC2612(address(EUR2)).nonces(trader2.addr);
        (uint8 v, bytes32 r, bytes32 s) = _permit(EUR2, trader2, vaultRelayer, 1 ether, nonce, 0xffffffff);
        // interaction for setting the approval with permit
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(EUR2),
                value: 0,
                callData: abi.encodeCall(IERC2612.permit, (trader2.addr, vaultRelayer, 1 ether, 0xffffffff, v, r, s))
            }),
            SettlementEncoder.InteractionStage.PRE
        );

        // buy 1 EUR1 with max 1 EUR2
        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                sellToken: EUR2,
                buyToken: EUR1,
                receiver: trader2.addr,
                sellAmount: 1 ether,
                buyAmount: 1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0,
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // set prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = EUR1;
        tokens[1] = EUR2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1;
        prices[1] = 1;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);
        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(EUR2.balanceOf(trader2.addr), 0, "permit didnt work");
    }

    function test_allows_setting_vault_relayer_approval_with_interactions() external {
        // mint and approve tokens to and from trader1
        EUR1.mint(trader1.addr, 1 ether);
        vm.prank(trader1.addr);
        EUR1.approve(vaultRelayer, type(uint256).max);

        // place order to sell 1 EUR1 for min 1 EUR2 from trader1
        encoder.signEncodeTrade(
            vm,
            trader1,
            GPv2Order.Data({
                sellToken: EUR1,
                buyToken: EUR2,
                receiver: trader1.addr,
                sellAmount: 1 ether,
                buyAmount: 1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0,
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_ERC20,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // mint some tokens to trader2
        EUR2.mint(trader2.addr, 1 ether);
        // deposit tokens into balancer internal balance
        vm.startPrank(trader2.addr);
        EUR2.approve(address(vault), type(uint256).max);
        IVault.UserBalanceOp[] memory ops = new IVault.UserBalanceOp[](1);
        ops[0] = IVault.UserBalanceOp({
            kind: IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: EUR2,
            amount: 1 ether,
            sender: trader2.addr,
            recipient: payable(trader2.addr)
        });
        vault.manageUserBalance(ops);
        vm.stopPrank();

        _grantBalancerActionRole(
            balancerVaultAuthorizer, address(vault), address(settlement), "setRelayerApproval(address,address,bool)"
        );
        bytes memory approval = abi.encodeCall(IBalancerVault.setRelayerApproval, (trader2.addr, vaultRelayer, true));
        (uint8 v, bytes32 r, bytes32 s) =
            _balancerSetRelayerApprovalSignature(trader2, approval, address(settlement), 0, 0xffffffff);
        encoder.addInteraction(
            GPv2Interaction.Data({
                target: address(vault),
                value: 0,
                callData: abi.encodePacked(approval, abi.encode(0xffffffff, v, r, s))
            }),
            SettlementEncoder.InteractionStage.PRE
        );

        encoder.signEncodeTrade(
            vm,
            trader2,
            GPv2Order.Data({
                sellToken: EUR2,
                buyToken: EUR1,
                receiver: trader2.addr,
                sellAmount: 1 ether,
                buyAmount: 1 ether,
                validTo: 0xffffffff,
                appData: bytes32(uint256(1)),
                feeAmount: 0,
                kind: GPv2Order.KIND_BUY,
                partiallyFillable: false,
                sellTokenBalance: GPv2Order.BALANCE_INTERNAL,
                buyTokenBalance: GPv2Order.BALANCE_ERC20
            }),
            domainSeparator,
            GPv2Signing.Scheme.Eip712,
            0
        );

        // set prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = EUR1;
        tokens[1] = EUR2;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1;
        prices[1] = 1;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);

        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(EUR2.balanceOf(trader2.addr), 0, "balancer signed approval didnt work");
    }

    function _permit(
        IERC20Mintable token,
        Vm.Wallet memory owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 ds = IERC2612(address(token)).DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(
            abi.encodePacked(
                hex"1901",
                ds,
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner.addr,
                        spender,
                        value,
                        nonce,
                        deadline
                    )
                )
            )
        );
        (v, r, s) = vm.sign(owner, digest);
    }

    function _balancerSetRelayerApprovalSignature(
        Vm.Wallet memory wallet,
        bytes memory cd,
        address sender,
        uint256 nonce,
        uint256 deadline
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 ds = IBalancerVault(address(vault)).getDomainSeparator();
        bytes memory ecd = abi.encode(
            keccak256("SetRelayerApproval(bytes calldata,address sender,uint256 nonce,uint256 deadline)"),
            keccak256(cd),
            sender,
            nonce,
            deadline
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", ds, keccak256(ecd)));
        (v, r, s) = vm.sign(wallet, digest);
    }
}
