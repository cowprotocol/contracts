// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Vm.sol";

interface IERC20Proxy {
    function addAuthorizedAddress(address) external;
}

interface IExchange {
    function registerAssetProxy(address) external;
    function isValidSignature(bytes32, address, bytes calldata) external view returns (bool);
    function fillOrder(ZeroExV2Order calldata, uint256, bytes calldata) external;
    function EIP712_DOMAIN_HASH() external view returns (bytes32);
}

struct ZeroExV2Order {
    address makerAddress;
    address takerAddress;
    address feeRecipientAddress;
    address sender;
    uint256 makerAssetAmount;
    uint256 takerAssetAmount;
    uint256 makerFee;
    uint256 takerFee;
    uint256 expirationTimeSeconds;
    uint256 salt;
    bytes makerAssetData;
    bytes takerAssetData;
}

string constant ZERO_EX_V2_ORDER_TYPE_STRING =
    "Order(address makerAddress,address takerAddress,address feeRecipientAddress,address senderAddress,uint256 makerAssetAmount,uint256 takerAssetAmount,uint256 makerFee,uint256 takerFee,uint256 expirationTimeSeconds,uint256 salt,bytes makerAssetData,bytes takerAssetData)";
bytes32 constant ZERO_EX_V2_ORDER_TYPE_HASH = keccak256(bytes(ZERO_EX_V2_ORDER_TYPE_STRING));

struct ZeroExV2SimpleOrder {
    address takerAddress;
    uint256 makerAssetAmount;
    uint256 takerAssetAmount;
    address makerAssetAddress;
    address takerAssetAddress;
}

library ZeroExV2 {
    function signSimpleOrder(Vm.Wallet memory wallet, address exchange, ZeroExV2SimpleOrder memory simpleOrder)
        internal
        returns (ZeroExV2Order memory order, bytes32 hash, uint8 v, bytes32 r, bytes32 s)
    {
        order = ZeroExV2Order({
            makerAddress: wallet.addr,
            takerAddress: address(0),
            feeRecipientAddress: address(0),
            sender: address(0),
            makerAssetAmount: simpleOrder.makerAssetAmount,
            takerAssetAmount: simpleOrder.takerAssetAmount,
            makerFee: 0,
            takerFee: 0,
            expirationTimeSeconds: 0xffffffff,
            salt: 0,
            makerAssetData: _encodeErc20AssetData(simpleOrder.makerAssetAddress),
            takerAssetData: _encodeErc20AssetData(simpleOrder.takerAssetAddress)
        });
        bytes32 domainSeparator = IExchange(exchange).EIP712_DOMAIN_HASH();

        hash = keccak256(abi.encodePacked(hex"1901", domainSeparator, _hashStruct(order)));
        (v, r, s) = _vm().sign(wallet, hash);
    }

    function deployExchange(address deployer)
        internal
        returns (address zrxToken, address erc20Proxy, address exchange)
    {
        Vm vm = _vm();
        vm.startPrank(deployer);
        zrxToken = _create(_getCode("ZRXToken"), 0);

        erc20Proxy = _create(_getCode("ERC20Proxy"), 0);

        bytes memory zrxAssetData = _encodeErc20AssetData(zrxToken);
        exchange = _create(abi.encodePacked(_getCode("Exchange"), abi.encode(zrxAssetData)), 0);

        IERC20Proxy(erc20Proxy).addAuthorizedAddress(exchange);
        IExchange(exchange).registerAssetProxy(erc20Proxy);

        vm.stopPrank();
    }

    function encodeSignature(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        return abi.encodePacked(v, r, s, uint8(0x02));
    }

    function _create(bytes memory initCode, uint256 value) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(value, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "contract creation failed");
    }

    function _vm() internal pure returns (Vm) {
        return Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    }

    function _encodeErc20AssetData(address token) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes4(keccak256(bytes("ERC20Token(address)"))), abi.encode(token));
    }

    function _hashStruct(ZeroExV2Order memory order) internal pure returns (bytes32) {
        // stack too deep hack:
        bytes32 schemaHash = ZERO_EX_V2_ORDER_TYPE_HASH;
        bytes32 makerAssetDataHash = keccak256(order.makerAssetData);
        bytes32 takerAssetDataHash = keccak256(order.takerAssetData);

        // Assembly for more efficiently computing:
        // keccak256(abi.encodePacked(
        //     EIP712_ORDER_SCHEMA_HASH,
        //     bytes32(order.makerAddress),
        //     bytes32(order.takerAddress),
        //     bytes32(order.feeRecipientAddress),
        //     bytes32(order.senderAddress),
        //     order.makerAssetAmount,
        //     order.takerAssetAmount,
        //     order.makerFee,
        //     order.takerFee,
        //     order.expirationTimeSeconds,
        //     order.salt,
        //     keccak256(order.makerAssetData),
        //     keccak256(order.takerAssetData)
        // ));

        bytes32 result;
        assembly {
            // Calculate memory addresses that will be swapped out before hashing
            let pos1 := sub(order, 32)
            let pos2 := add(order, 320)
            let pos3 := add(order, 352)

            // Backup
            let temp1 := mload(pos1)
            let temp2 := mload(pos2)
            let temp3 := mload(pos3)

            // Hash in place
            mstore(pos1, schemaHash)
            mstore(pos2, makerAssetDataHash)
            mstore(pos3, takerAssetDataHash)
            result := keccak256(pos1, 416)

            // Restore
            mstore(pos1, temp1)
            mstore(pos2, temp2)
            mstore(pos3, temp3)
        }
        return result;
    }

    function _getCode(string memory artifactName) internal view returns (bytes memory) {
        Vm vm = _vm();
        string memory data = vm.readFile(
            string(abi.encodePacked("node_modules/@0x/contract-artifacts-v2/lib/artifacts/", artifactName, ".json"))
        );
        return vm.parseJsonBytes(data, ".compilerOutput.evm.bytecode.object");
    }
}
