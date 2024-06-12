// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Test.sol";
import {Bytes} from "./Bytes.sol";

library Bytecode {
    using Bytes for bytes;

    struct ImmutableReference {
        uint256 length;
        uint256 start;
    }

    /// @dev Return all the immutables from a deployed contract
    function deployedImmutables(Vm vm, string memory contractName, address which)
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
                revert("Every immutable is expected to have at least a reference entry");
            }

            // Only interested in the first occurence of the ith immutable reference
            ImmutableReference memory r = jsonImmutables[0];
            immutables[i] = which.code.slice(r.start, r.length);
        }
    }

    function toMetadata(bytes memory bytecode) internal pure returns (bytes memory metadata) {
        // The metadata is contained at the last 53 bytes of the deployed bytecode
        metadata = bytecode.slice(bytecode.length - 53, 53);
    }
}
