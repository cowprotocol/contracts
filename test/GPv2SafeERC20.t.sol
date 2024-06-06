// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {GPv2SafeERC20TestInterface} from "./GPv2SafeERC20/GPv2SafeERC20TestInterface.sol";

contract GPv2SafeERC20TestHelper is Test {
    GPv2SafeERC20TestInterface executor;
    address recipient = makeAddr("GPv2SafeERC20TestHelper: recipient");

    function setUp() public {
        executor = new GPv2SafeERC20TestInterface();
    }
}

contract GPv2SafeERC20Transfer is GPv2SafeERC20TestHelper {
    function test_succeeds_when_internal_call_succeeds() public {
        uint256 amount = 13.37 ether;

        IERC20 standardToken = IERC20(makeAddr("standard token"));
        vm.mockCall(
            address(standardToken),
            abi.encodeCall(IERC20.transfer, (recipient, amount)),
            abi.encode(true)
        );

        executor.transfer(standardToken, recipient, amount);
    }

    function test_reverts_on_failed_internal_call() public {
        uint256 amount = 42 ether;

        IERC20 revertingToken = IERC20(makeAddr("reverting token"));

        vm.mockCallRevert(
            address(revertingToken),
            abi.encodeCall(IERC20.transfer, (recipient, amount)),
            bytes("test error")
        );

        vm.expectRevert("test error");
        executor.transfer(revertingToken, recipient, amount);
    }

    function test_reverts_when_calling_a_non_contract() public {
        uint256 amount = 4.2 ether;

        IERC20 standardToken = IERC20(makeAddr("address without code"));

        vm.expectRevert("GPv2: not a contract");
        executor.transfer(standardToken, recipient, amount);
    }

    function test_does_not_revert_when_the_internal_call_has_no_return_data()
        public
    {
        uint256 amount = 13.37 ether;

        IERC20 tokenNoReturnValue = IERC20(
            makeAddr("does not return on transfer")
        );

        vm.mockCall(
            address(tokenNoReturnValue),
            abi.encodeCall(IERC20.transfer, (recipient, amount)),
            hex""
        );

        executor.transfer(tokenNoReturnValue, recipient, amount);
    }

    function test_reverts_when_the_internal_call_returns_false() public {
        uint256 amount = 13.37 ether;

        IERC20 tokenReturnsFalse = IERC20(
            makeAddr("returns false on transfer")
        );

        vm.mockCall(
            address(tokenReturnsFalse),
            abi.encodeCall(IERC20.transfer, (recipient, amount)),
            abi.encode(false)
        );

        vm.expectRevert("GPv2: failed transfer");
        executor.transfer(tokenReturnsFalse, recipient, amount);
    }

    function test_reverts_when_too_much_data_is_returned() public {
        uint256 amount = 1 ether;

        IERC20 tokenReturnsTooMuchData = IERC20(
            makeAddr("returns too much data transfer")
        );

        vm.mockCall(
            address(tokenReturnsTooMuchData),
            abi.encodeCall(IERC20.transfer, (recipient, amount)),
            abi.encodePacked(new bytes(256))
        );

        vm.expectRevert("GPv2: malformed transfer result");
        executor.transfer(tokenReturnsTooMuchData, recipient, amount);
    }

    function test_coerces_invalid_abi_encoded_bool() public {
        uint256 amount = 1 ether;

        IERC20 tokenReturnsLargeUint = IERC20(
            makeAddr("returns uint256 larger than 1")
        );

        vm.mockCall(
            address(tokenReturnsLargeUint),
            abi.encodeCall(IERC20.transfer, (recipient, amount)),
            abi.encode(42)
        );

        executor.transfer(tokenReturnsLargeUint, recipient, amount);
    }
}

contract GPv2SafeERC20TransferFrom is GPv2SafeERC20TestHelper {
    address sender = makeAddr("GPv2SafeERC20TransferFrom: transfer sender");

    function test_succeeds_when_internal_call_succeeds() public {
        uint256 amount = 13.37 ether;

        IERC20 standardToken = IERC20(makeAddr("standard token"));
        vm.mockCall(
            address(standardToken),
            abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)),
            abi.encode(true)
        );

        executor.transferFrom(standardToken, sender, recipient, amount);
    }

    function test_reverts_on_failed_internal_call() public {
        uint256 amount = 42 ether;

        IERC20 revertingToken = IERC20(makeAddr("reverting token"));

        vm.mockCallRevert(
            address(revertingToken),
            abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)),
            bytes("test error")
        );

        vm.expectRevert("test error");
        executor.transferFrom(revertingToken, sender, recipient, amount);
    }

    function test_reverts_when_calling_a_non_contract() public {
        uint256 amount = 4.2 ether;

        IERC20 standardToken = IERC20(makeAddr("address without code"));

        vm.expectRevert("GPv2: not a contract");
        executor.transferFrom(standardToken, sender, recipient, amount);
    }

    function test_does_not_revert_when_the_internal_call_has_no_return_data()
        public
    {
        uint256 amount = 13.37 ether;

        IERC20 tokenNoReturnValue = IERC20(
            makeAddr("does not return on transfer")
        );

        vm.mockCall(
            address(tokenNoReturnValue),
            abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)),
            hex""
        );

        executor.transferFrom(tokenNoReturnValue, sender, recipient, amount);
    }

    function test_reverts_when_the_internal_call_returns_false() public {
        uint256 amount = 13.37 ether;

        IERC20 tokenReturnsFalse = IERC20(
            makeAddr("returns false on transfer")
        );

        vm.mockCall(
            address(tokenReturnsFalse),
            abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)),
            abi.encode(false)
        );

        vm.expectRevert("GPv2: failed transferFrom");
        executor.transferFrom(tokenReturnsFalse, sender, recipient, amount);
    }

    function test_reverts_when_too_much_data_is_returned() public {
        uint256 amount = 1 ether;

        IERC20 tokenReturnsTooMuchData = IERC20(
            makeAddr("returns too much data transfer")
        );

        vm.mockCall(
            address(tokenReturnsTooMuchData),
            abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)),
            abi.encodePacked(new bytes(256))
        );

        vm.expectRevert("GPv2: malformed transfer result");
        executor.transferFrom(
            tokenReturnsTooMuchData,
            sender,
            recipient,
            amount
        );
    }

    function test_coerces_invalid_abi_encoded_bool() public {
        uint256 amount = 1 ether;

        IERC20 tokenReturnsLargeUint = IERC20(
            makeAddr("returns uint256 larger than 1")
        );

        vm.mockCall(
            address(tokenReturnsLargeUint),
            abi.encodeCall(IERC20.transferFrom, (sender, recipient, amount)),
            abi.encode(42)
        );

        executor.transferFrom(tokenReturnsLargeUint, sender, recipient, amount);
    }
}
