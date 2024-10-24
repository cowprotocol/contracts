// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

import {Helper} from "./Helper.sol";

interface IEIP173Proxy {
    function owner() external view returns (address);
}

// ref: https://github.com/wighawag/hardhat-deploy/blob/e0ffcf9e7dc92b246e832c4d175f9dbd8b6df14d/solc_0.8/proxy/EIP173Proxy.sol
bytes32 constant EIP173_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

contract DeploymentTest is Helper(false) {
    event Metadata(string, bytes);

    function test__same_built_and_deployed_bytecode_metadata__authenticator() external {
        _assertBuiltAndDeployedMetadataCoincide(address(allowListImpl), "GPv2AllowListAuthentication");
    }

    function test__same_built_and_deployed_bytecode_metadata__settlement() external {
        _assertBuiltAndDeployedMetadataCoincide(address(settlement), "GPv2Settlement");
    }

    function test__same_built_and_deployed_bytecode_metadata__vault_relayer() external {
        _assertBuiltAndDeployedMetadataCoincide(address(vaultRelayer), "GPv2VaultRelayer");
    }

    function test__determininstic_addresses__authenticator__proxy() external view {
        assertEq(
            _computeCreate2Addr(
                abi.encodePacked(
                    vm.getCode("EIP173Proxy"),
                    abi.encode(
                        _implementationAddress(address(allowList)),
                        owner,
                        abi.encodeCall(GPv2AllowListAuthentication.initializeManager, (owner))
                    )
                )
            ),
            address(authenticator),
            "authenticator address not as expected"
        );
    }

    function test__determininstic_addresses__authenticator__implementation() external view {
        assertEq(
            _computeCreate2Addr(vm.getCode("GPv2AllowListAuthentication")),
            _implementationAddress(address(allowList)),
            "authenticator impl address not as expected"
        );
    }

    function test__determininstic_addresses__settlement() external view {
        assertEq(
            _computeCreate2Addr(
                abi.encodePacked(vm.getCode("GPv2Settlement"), abi.encode(address(authenticator), address(vault)))
            ),
            address(settlement),
            "settlement address not as expected"
        );
    }

    function test__authorization__authenticator_has_dedicated_owner() external view {
        assertEq(IEIP173Proxy(address(allowList)).owner(), owner, "owner not as expected");
    }

    function test__authorization__authenticator_has_dedicated_manager() external view {
        assertEq(allowList.manager(), owner, "manager not as expected");
    }

    function _assertBuiltAndDeployedMetadataCoincide(address addr, string memory artifactName) internal {
        bytes memory deployedCode = vm.getDeployedCode(artifactName);
        assertEq(
            keccak256(_getMetadata(string(abi.encodePacked("deployed ", artifactName)), addr.code)),
            keccak256(_getMetadata(artifactName, deployedCode)),
            "metadata doesnt match"
        );
    }

    function _getMetadata(string memory hint, bytes memory bytecode) internal returns (bytes memory metadata) {
        assembly ("memory-safe") {
            // the last two bytes encode the size of the cbor encoded metadata
            let bytecodeSize := mload(bytecode)
            let bytecodeStart := add(bytecode, 0x20)
            let cborSizeOffset := add(bytecodeStart, sub(bytecodeSize, 0x20))
            let cborSize := and(mload(cborSizeOffset), 0xffff)

            // copy the metadata out
            metadata := mload(0x40)
            let metadataSize := add(cborSize, 0x02)
            mstore(metadata, metadataSize)
            let metadataOffset := add(bytecodeStart, sub(bytecodeSize, metadataSize))
            mcopy(add(metadata, 0x20), metadataOffset, metadataSize)

            // update free memory ptr
            mstore(0x40, add(metadata, add(metadataSize, 0x20)))
        }
        emit Metadata(hint, metadata);
    }

    function _computeCreate2Addr(bytes memory initCode) internal view returns (address) {
        return vm.computeCreate2Address(SALT, hashInitCode(initCode), deployer);
    }

    function _implementationAddress(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, EIP173_IMPLEMENTATION_SLOT))));
    }
}
