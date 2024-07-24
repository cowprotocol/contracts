// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {console} from "forge-std/Script.sol";

import {GPv2AllowListAuthentication} from "../src/contracts/GPv2AllowListAuthentication.sol";

import {ERC165, ERC173} from "./interfaces/ERC173.sol";
import {NetworksJson} from "./lib/NetworksJson.sol";

contract TransferOwnership is NetworksJson {
    // Required input
    string private constant INPUT_ENV_NEW_OWNER = "NEW_OWNER";
    string private constant INPUT_ENV_RESET_MANAGER = "RESET_MANAGER";
    // Optional input
    string private constant INPUT_ENV_AUTHENTICATOR_PROXY = "AUTHENTICATOR_PROXY";

    NetworksJson internal networksJson;

    struct ScriptParams {
        address newOwner;
        bool resetManager;
        ERC173 authenticatorProxy;
    }

    constructor() {
        networksJson = new NetworksJson();
    }

    function run() public virtual {
        ScriptParams memory params = paramsFromEnv();
        runWith(params);
    }

    function runWith(ScriptParams memory params) public {
        console.log(string.concat("Using account ", vm.toString(msg.sender)));

        checkIsProxy(address(params.authenticatorProxy));

        address owner = params.authenticatorProxy.owner();
        if (owner != msg.sender) {
            revert(string.concat("Account does NOT match current owner ", vm.toString(owner)));
        }

        GPv2AllowListAuthentication authenticator = GPv2AllowListAuthentication(address(params.authenticatorProxy));

        // Make sure to reset the manager BEFORE transferring ownership, or else
        // we will not be able to do it once we lose permissions.
        if (params.resetManager) {
            console.log(
                string.concat(
                    "Setting new solver manager from ",
                    vm.toString(authenticator.manager()),
                    " to ",
                    vm.toString(params.newOwner)
                )
            );
            vm.broadcast(msg.sender);
            authenticator.setManager(params.newOwner);
            console.log("Set new solver manager account.");
        }

        console.log(
            string.concat(
                "Setting new authenticator proxy owner from ", vm.toString(owner), " to ", vm.toString(params.newOwner)
            )
        );
        vm.broadcast(msg.sender);
        params.authenticatorProxy.transferOwnership(params.newOwner);
        console.log("Set new owner of the authenticator proxy.");
    }

    function paramsFromEnv() internal view returns (ScriptParams memory) {
        address newOwner = vm.envAddress(INPUT_ENV_NEW_OWNER);
        bool resetManager = vm.envBool(INPUT_ENV_RESET_MANAGER);

        address authenticatorProxy;
        try vm.envAddress(INPUT_ENV_AUTHENTICATOR_PROXY) returns (address env) {
            authenticatorProxy = env;
        } catch {
            try networksJson.addressOf("GPv2AllowListAuthentication_Proxy") returns (address addr) {
                authenticatorProxy = addr;
            } catch {
                revert(
                    string.concat(
                        "Could not find default authenticator address in file ",
                        networksJson.PATH(),
                        " for network with chain id ",
                        vm.toString(block.chainid),
                        ". Export variable ",
                        INPUT_ENV_AUTHENTICATOR_PROXY,
                        " to manually specify a non-standard address for the authenticator."
                    )
                );
            }
        }

        return ScriptParams({
            newOwner: newOwner,
            resetManager: resetManager,
            authenticatorProxy: ERC173(authenticatorProxy)
        });
    }

    function checkIsProxy(address candidate) internal view {
        if (address(candidate).code.length == 0) {
            revert(string.concat("No code at target authenticator proxy ", vm.toString(address(candidate)), "."));
        }

        bool isERC173;
        try ERC165(candidate).supportsInterface(type(ERC173).interfaceId) returns (bool isERC173_) {
            isERC173 = isERC173_;
        } catch {
            isERC173 = false;
        }
        if (!isERC173) {
            revert(
                string.concat(
                    "Not a valid proxy contract: target address ",
                    vm.toString(address(candidate)),
                    " does not support the ERC173 interface."
                )
            );
        }
    }
}
