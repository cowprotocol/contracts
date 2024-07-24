// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2VaultRelayer} from "src/contracts/GPv2VaultRelayer.sol";
import {Bytecode} from "test/libraries/Bytecode.sol";

import {Helper, Vm} from "./Helper.sol";

// solhint-disable func-name-mixedcase
contract DeploymentParams is Helper {
    using Bytecode for Vm;
    using Bytecode for bytes;

    function test_settlement_sets_authenticator() public view {
        assertEq(address(authenticator), address(settlement.authenticator()));
    }

    function test_settlement_sets_vault() public view {
        assertEq(address(vault), address(settlement.vault()));
    }

    function test_settlement_deployment_deploys_a_vault_relayer() public view {
        GPv2VaultRelayer relayer = GPv2VaultRelayer(settlement.vaultRelayer());
        bytes memory deployedBytecode = address(relayer).code;
        assertEq(deployedBytecode.toMetadata(), type(GPv2VaultRelayer).creationCode.toMetadata());
    }

    function test_settlement_deployment_sets_vault_relayer_immutables() public view {
        bytes[] memory rawImmutables = vm.deployedImmutables("GPv2VaultRelayer", address(settlement.vaultRelayer()));
        assertEq(rawImmutables.length, 2, "Invalid number of immutables");
        assertEq(rawImmutables[0], abi.encode(address(settlement)), "invalid creator address");
        assertEq(rawImmutables[1], abi.encode(address(vault)), "invalid vault address");
    }
}
