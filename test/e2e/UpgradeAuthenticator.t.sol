// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

import {GPv2AllowListAuthenticationV2} from "../src/GPv2AllowListAuthenticationV2.sol";
import {Helper} from "./Helper.sol";

interface IEIP173Proxy {
    function upgradeTo(address) external;
    function transferOwnership(address) external;
    function owner() external view returns (address);
}

contract UpgradeAuthenticatorTest is Helper(false) {
    GPv2AllowListAuthenticationV2 v2Impl;

    function setUp() public override {
        super.setUp();
        v2Impl = new GPv2AllowListAuthenticationV2();
    }

    function test_should_upgrade_authenticator() external {
        vm.expectRevert();
        GPv2AllowListAuthenticationV2(address(authenticator)).newMethod();

        vm.prank(owner);
        IEIP173Proxy(address(authenticator)).upgradeTo(address(v2Impl));

        assertEq(
            GPv2AllowListAuthenticationV2(address(authenticator)).newMethod(), 1337, "proxy didnt update as expected"
        );
    }

    function test_should_preserve_storage() external {
        address newSolver = makeAddr("newSolver");
        address newManager = makeAddr("newManager");

        vm.startPrank(owner);
        GPv2AllowListAuthentication(address(authenticator)).addSolver(newSolver);
        GPv2AllowListAuthentication(address(authenticator)).setManager(newManager);

        IEIP173Proxy(address(authenticator)).upgradeTo(address(v2Impl));
        vm.stopPrank();

        assertEq(authenticator.isSolver(newSolver), true, "solver not retained in storage after proxy upgrade");
        assertEq(
            GPv2AllowListAuthentication(address(authenticator)).manager(),
            newManager,
            "manager not retained in storage after proxy upgrade"
        );
    }

    function test_should_allow_proxy_owner_to_change_manager() external {
        // transfer ownership to a new address and then assert the behavior
        // to have a proxy owner that is different address than manager
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        IEIP173Proxy(address(authenticator)).transferOwnership(newOwner);

        address newManager = makeAddr("newManager");
        vm.prank(newOwner);
        GPv2AllowListAuthentication(address(authenticator)).setManager(newManager);

        assertEq(
            GPv2AllowListAuthentication(address(authenticator)).manager(),
            newManager,
            "proxy owner couldnt update manager"
        );
    }

    function test_should_be_able_to_transfer_proxy_ownership() external {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        IEIP173Proxy(address(authenticator)).transferOwnership(newOwner);

        assertEq(IEIP173Proxy(address(authenticator)).owner(), newOwner, "ownership didnt transfer as expected");
    }

    function test_should_revert_when_upgrading_with_the_authentication_manager() external {
        address newManager = makeAddr("newManager");
        vm.prank(owner);
        GPv2AllowListAuthentication(address(authenticator)).setManager(newManager);

        vm.prank(newManager);
        vm.expectRevert("NOT_AUTHORIZED");
        IEIP173Proxy(address(authenticator)).upgradeTo(address(v2Impl));
    }

    function test_should_revert_when_not_upgrading_with_the_proxy_owner() external {
        address nobody = makeAddr("nobody");
        vm.prank(nobody);
        vm.expectRevert("NOT_AUTHORIZED");
        IEIP173Proxy(address(authenticator)).upgradeTo(address(v2Impl));
    }
}
