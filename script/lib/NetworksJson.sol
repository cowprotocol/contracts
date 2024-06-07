// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

contract NetworksJson is Script {
    string public constant PATH = "./networks.json";

    function addressOf(string memory contractName) public view returns (address) {
        return addressByChainId(contractName, block.chainid);
    }

    function addressByChainId(string memory contractName, uint256 chainId) public view returns (address) {
        string memory networksJson = vm.readFile(PATH);
        return
            vm.parseJsonAddress(networksJson, string.concat(".", contractName, ".", vm.toString(chainId), ".address"));
    }
}
