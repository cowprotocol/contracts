// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";

library Bytecode {
    // solhint-disable-next-line const-name-snakecase
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    error SliceOutOfBounds();
    error NoImmutablesFound();

    struct ImmutableReference {
        uint256 length;
        uint256 start;
    }

    /// @dev Return all the immutables from a deployed contract
    function deployedImmutables(address which, string memory contractName)
        internal
        view
        returns (bytes[] memory immutables)
    {
        string memory json =
            vm.readFile(string.concat(vm.projectRoot(), "/out/", contractName, ".sol/", contractName, ".json"));
        string memory jsonPath = ".deployedBytecode.immutableReferences";

        // Get a list of the immutables
        string[] memory keys = vm.parseJsonKeys(json, jsonPath);
        immutables = new bytes[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            bytes memory j = vm.parseJson(json, string.concat(jsonPath, ".", keys[i]));
            ImmutableReference[] memory jsonImmutables = abi.decode(j, (ImmutableReference[]));

            if (jsonImmutables.length == 0) {
                revert NoImmutablesFound();
            }

            // Only interested in the first occurence of the ith immutable reference
            ImmutableReference memory r = jsonImmutables[0];
            bytes memory data = new bytes(r.length);
            // solhint-disable-next-line no-inline-assembly
            assembly ("memory-safe") {
                let size := mload(data)
                let offset := add(data, 0x20)
                extcodecopy(which, offset, mload(add(r, 0x20)), size)
            }

            immutables[i] = data;
        }
    }

    function bytecodeMetadataMatches(bytes memory deployedBytecode, bytes memory compiledBytecode)
        internal
        pure
        returns (bool)
    {
        return keccak256(bytecodeMetadata(deployedBytecode)) == keccak256(bytecodeMetadata(compiledBytecode));
    }

    function bytecodeMetadata(bytes memory bytecode) internal pure returns (bytes memory metadata) {
        // The metadata is contained at the last 53 bytes of the deployed bytecode
        metadata = bytesSlice(bytecode, bytecode.length - 53, 53);
    }

    function bytesSlice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory slice) {
        if (data.length < start + length) {
            revert SliceOutOfBounds();
        }

        slice = new bytes(length);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy the data from the source to the destination
            let src := add(add(data, 0x20), start)
            let dst := add(slice, 0x20)
            mcopy(dst, src, length)
        }
    }
}
