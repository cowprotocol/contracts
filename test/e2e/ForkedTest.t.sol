// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Helper} from "test/GPv2Settlement/Helper.sol";

address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

interface IAuthorizer {
    function grantRole(bytes32, address) external;
}

contract ForkedTest is Helper {
    uint256 forkId;
    address vaultRelayer;

    function setUp() public virtual override {
        super.setUp();

        uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER");
        string memory forkUrl = vm.envString("FORK_URL");
        forkId = vm.createSelectFork(forkUrl, blockNumber);

        // clear the mock revert on vault address
        vm.clearMockedCalls();

        // set vault relayer
        vaultRelayer = address(settlement.vaultRelayer());

        // deploy the balancer vault
        _deployBalancerVault();
    }

    function _deployBalancerVault() internal {
        bytes memory authorizerInitCode = abi.encodePacked(_getBalancerBytecode("Authorizer"), abi.encode(owner));
        address authorizer = _create(authorizerInitCode, 0);

        bytes memory vaultInitCode = abi.encodePacked(_getBalancerBytecode("Vault"), abi.encode(authorizer, WETH, 0, 0));
        vm.record();
        address deployedVault = _create(vaultInitCode, 0);
        (, bytes32[] memory writeSlots) = vm.accesses(deployedVault);

        // replay storage writes made in the constructor and set the balancer code
        vm.etch(address(vault), deployedVault.code);
        for (uint256 i = 0; i < writeSlots.length; i++) {
            bytes32 slot = writeSlots[i];
            bytes32 val = vm.load(deployedVault, slot);
            vm.store(address(vault), slot, val);
        }

        // grant required roles
        vm.startPrank(owner);
        IAuthorizer(authorizer).grantRole(
            _getActionId("manageUserBalance((uint8,address,uint256,address,address)[])", address(deployedVault)),
            vaultRelayer
        );
        IAuthorizer(authorizer).grantRole(
            _getActionId(
                "batchSwap(uint8,(bytes32,uint256,uint256,uint256,bytes)[],address[],(address,bool,address,bool),int256[],uint256)",
                address(deployedVault)
            ),
            vaultRelayer
        );
        vm.stopPrank();
    }

    function _getActionId(string memory fnDef, address vaultAddr) internal pure returns (bytes32) {
        bytes32 hash = keccak256(bytes(fnDef));
        bytes4 selector = bytes4(hash);
        return keccak256(abi.encodePacked(uint256(uint160(vaultAddr)), selector));
    }

    function _getBalancerBytecode(string memory artifactName) internal view returns (bytes memory) {
        string memory data = vm.readFile(string(abi.encodePacked("balancer/", artifactName, ".json")));
        return vm.parseJsonBytes(data, ".bytecode");
    }

    function _create(bytes memory initCode, uint256 value) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(value, add(initCode, 0x20), mload(initCode))
        }
    }
}
