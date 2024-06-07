// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2SettlementHelper} from "./GPv2SettlementHelper.sol";
import {GPv2VaultRelayer} from "src/contracts/GPv2VaultRelayer.sol";
import {Bytecode} from "test/libraries/Bytecode.sol";

// solhint-disable func-name-mixedcase
contract DeploymentParamsTest is GPv2SettlementHelper {
    using Bytecode for address;
    using Bytecode for bytes;

    function test_settlement_sets_authenticator() public view {
        assertEq(address(authenticator), address(settlement.authenticator()));
    }

    function test_settlement_sets_vault() public view {
        assertEq(address(vault), address(settlement.vault()));
    }

    function test_vaultRelayer_deploys() public view {
        GPv2VaultRelayer relayer = GPv2VaultRelayer(settlement.vaultRelayer());
        bytes memory deployedBytecode = address(relayer).code;
        assertTrue(deployedBytecode.bytecodeMetadataMatches(type(GPv2VaultRelayer).creationCode));
    }

    function test_vaultRelayer_sets_immutables_creator_and_vault() public view {
        bytes[] memory rawImmutables = address(settlement.vaultRelayer()).deployedImmutables("GPv2VaultRelayer");
        assertEq(rawImmutables.length, 2, "Invalid number of immutables");
        assertEq(rawImmutables[0], abi.encode(address(settlement)), "Invalid creator address");
        assertEq(rawImmutables[1], abi.encode(address(vault)), "Invalid vault address");
    }
}
