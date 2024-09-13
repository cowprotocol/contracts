// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";
import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing} from "src/contracts/mixins/GPv2Signing.sol";

import {Eip712} from "../libraries/Eip712.sol";

import {Sign} from "../libraries/Sign.sol";
import {SettlementEncoder} from "../libraries/encoders/SettlementEncoder.sol";
import {Registry, TokenRegistry} from "../libraries/encoders/TokenRegistry.sol";
import {Helper, IERC20Mintable} from "./Helper.sol";

using SettlementEncoder for SettlementEncoder.State;
using TokenRegistry for TokenRegistry.State;
using TokenRegistry for Registry;

interface ISafeProxyFactory {
    function createProxy(address singleton, bytes calldata data) external returns (ISafe);
}

interface ISafe {
    enum Operation {
        Call,
        DelegateCall
    }

    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);

    function nonce() external view returns (uint256);

    function getMessageHash(bytes calldata) external view returns (bytes32);

    function isValidSignature(bytes32, bytes calldata) external view returns (bytes4);
}

ISafeProxyFactory constant SAFE_PROXY_FACTORY = ISafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);
address constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
address constant SAFE_COMPATIBILITY_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
bytes4 constant EIP1271_MAGICVALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

contract ContractOrdersWithGnosisSafeTest is Helper(true) {
    IERC20Mintable DAI;
    IERC20Mintable WETH;

    ISafe safe;

    Vm.Wallet signer1;
    Vm.Wallet signer2;
    Vm.Wallet signer3;
    Vm.Wallet signer4;
    Vm.Wallet signer5;

    function setUp() public override {
        super.setUp();

        DAI = deployMintableErc20("DAI", "DAI");
        WETH = deployMintableErc20("WETH", "WETH");

        signer1 = vm.createWallet("signer1");
        signer2 = vm.createWallet("signer2");
        signer3 = vm.createWallet("signer3");
        signer4 = vm.createWallet("signer4");
        signer5 = vm.createWallet("signer5");

        address[] memory signers = new address[](5);
        signers[0] = signer1.addr;
        signers[1] = signer2.addr;
        signers[2] = signer3.addr;
        signers[3] = signer4.addr;
        signers[4] = signer5.addr;

        bytes memory data = abi.encodeCall(
            ISafe.setup,
            (signers, 2, address(0), hex"", SAFE_COMPATIBILITY_FALLBACK_HANDLER, address(0), 0, payable(address(0)))
        );
        safe = SAFE_PROXY_FACTORY.createProxy(SAFE_SINGLETON, data);
    }

    function test_should_settle_matching_orders() external {
        // EOA trader: sell 1 WETH for  900 DAI
        // Safe:       buy  1 WETH for 1100 DAI
        // Settlement price at 1000 DAI for 1 WETH.

        // mint some tokens to trader
        WETH.mint(trader.addr, 1.001 ether);
        // approve the tokens for trading on settlement contract
        vm.prank(trader.addr);
        WETH.approve(vaultRelayer, type(uint256).max);

        // place order to sell 1 WETH for min 900 DAI
        encoder.signEncodeTrade(
            vm,
            trader,
            GPv2Order.Data({
                kind: GPv2Order.KIND_SELL,
                partiallyFillable: false,
                sellToken: WETH,
                buyToken: DAI,
                sellAmount: 1 ether,
                buyAmount: 900 ether,
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

        // mint some dai to the safe
        DAI.mint(address(safe), 1110 ether);
        // approve dai for trading on settlement contract
        _execSafeTransaction(
            safe, address(DAI), 0, abi.encodeCall(IERC20.approve, (vaultRelayer, type(uint256).max)), signer1, signer2
        );
        assertEq(DAI.allowance(address(safe), vaultRelayer), type(uint256).max, "allowance not as expected");

        // place order to buy 1 WETH with max 1100 DAI
        GPv2Order.Data memory order = GPv2Order.Data({
            kind: GPv2Order.KIND_BUY,
            partiallyFillable: false,
            sellToken: DAI,
            buyToken: WETH,
            sellAmount: 1100 ether,
            buyAmount: 1 ether,
            feeAmount: 10 ether,
            validTo: 0xffffffff,
            appData: bytes32(uint256(1)),
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20,
            receiver: GPv2Order.RECEIVER_SAME_AS_OWNER
        });

        bytes32 orderHash = Eip712.typedDataHash(Eip712.toEip712SignedStruct(order), domainSeparator);
        bytes32 safeMessageHash = safe.getMessageHash(abi.encode(orderHash));
        bytes memory signatures = _safeSignature(signer3, signer4, safeMessageHash);

        assertEq(safe.isValidSignature(orderHash, signatures), EIP1271_MAGICVALUE, "invalid signature for the order");

        encoder.encodeTrade(
            order,
            Sign.Signature({scheme: GPv2Signing.Scheme.Eip1271, data: abi.encodePacked(address(safe), signatures)}),
            0
        );

        // set token prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = DAI;
        tokens[1] = WETH;
        uint256[] memory prices = new uint256[](2);
        prices[0] = 1 ether;
        prices[1] = 1000 ether;
        encoder.tokenRegistry.tokenRegistry().setPrices(tokens, prices);

        SettlementEncoder.EncodedSettlement memory encodedSettlement = encoder.encode(settlement);

        vm.prank(solver);
        settle(encodedSettlement);

        assertEq(WETH.balanceOf(trader.addr), 0, "trader weth balance not as expected");
        assertEq(DAI.balanceOf(trader.addr), 1000 ether, "trader dai balance not as expected");

        assertEq(WETH.balanceOf(address(safe)), 1 ether, "safe weth balance not as expected");
        assertEq(DAI.balanceOf(address(safe)), 100 ether, "safe dai balance not as expected");

        assertEq(WETH.balanceOf(address(settlement)), 0.001 ether, "settlement weth fee not as expected");
        assertEq(DAI.balanceOf(address(settlement)), 10 ether, "settlement dai fee not as expected");
    }

    function _execSafeTransaction(
        ISafe safe_,
        address to,
        uint256 value,
        bytes memory data,
        Vm.Wallet memory signer1_,
        Vm.Wallet memory signer2_
    ) internal {
        uint256 nonce = safe_.nonce();
        bytes32 hash =
            safe_.getTransactionHash(to, value, data, ISafe.Operation.Call, 0, 0, 0, address(0), address(0), nonce);
        bytes memory signatures = _safeSignature(signer1_, signer2_, hash);
        safe_.execTransaction(
            to, value, data, ISafe.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures
        );
    }

    function _sign(Vm.Wallet memory wallet, bytes32 hash) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet, hash);
        return abi.encodePacked(r, s, v);
    }

    function _safeSignature(Vm.Wallet memory signer1_, Vm.Wallet memory signer2_, bytes32 hash)
        internal
        returns (bytes memory)
    {
        bytes memory signature1 = _sign(signer1_, hash);
        bytes memory signature2 = _sign(signer2_, hash);
        bytes memory signatures = signer1_.addr < signer2_.addr
            ? abi.encodePacked(signature1, signature2)
            : abi.encodePacked(signature2, signature1);
        return signatures;
    }
}
