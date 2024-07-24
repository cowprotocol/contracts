// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {Helper} from "./Helper.sol";

contract Transfer is Helper {
    function test_succeeds_when_internal_call_succeeds() public {
        uint256 amount = 13.37 ether;

        IERC20 standardToken = IERC20(makeAddr("standard token"));
        vm.mockCall(address(standardToken), abi.encodeCall(IERC20.transfer, (recipient, amount)), abi.encode(true));

        executor.transfer(standardToken, recipient, amount);
    }

    function test_reverts_on_failed_internal_call() public {
        uint256 amount = 42 ether;

        IERC20 revertingToken = IERC20(makeAddr("reverting token"));

        vm.mockCallRevert(
            address(revertingToken), abi.encodeCall(IERC20.transfer, (recipient, amount)), bytes("test error")
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

    function test_does_not_revert_when_the_internal_call_has_no_return_data() public {
        uint256 amount = 13.37 ether;

        IERC20 tokenNoReturnValue = IERC20(makeAddr("does not return on transfer"));

        vm.mockCall(address(tokenNoReturnValue), abi.encodeCall(IERC20.transfer, (recipient, amount)), hex"");

        executor.transfer(tokenNoReturnValue, recipient, amount);
    }

    function test_reverts_when_the_internal_call_returns_false() public {
        uint256 amount = 13.37 ether;

        IERC20 tokenReturnsFalse = IERC20(makeAddr("returns false on transfer"));

        vm.mockCall(address(tokenReturnsFalse), abi.encodeCall(IERC20.transfer, (recipient, amount)), abi.encode(false));

        vm.expectRevert("GPv2: failed transfer");
        executor.transfer(tokenReturnsFalse, recipient, amount);
    }

    function test_reverts_when_too_much_data_is_returned() public {
        uint256 amount = 1 ether;

        IERC20 tokenReturnsTooMuchData = IERC20(makeAddr("returns too much data transfer"));

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

        IERC20 tokenReturnsLargeUint = IERC20(makeAddr("returns uint256 larger than 1"));

        vm.mockCall(
            address(tokenReturnsLargeUint), abi.encodeCall(IERC20.transfer, (recipient, amount)), abi.encode(42)
        );

        executor.transfer(tokenReturnsLargeUint, recipient, amount);
    }
}
