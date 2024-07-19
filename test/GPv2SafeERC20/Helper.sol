// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "src/contracts/interfaces/IERC20.sol";
import {GPv2SafeERC20} from "src/contracts/libraries/GPv2SafeERC20.sol";

contract Harness {
    using GPv2SafeERC20 for IERC20;

    function transfer(IERC20 token, address to, uint256 value) public {
        token.safeTransfer(to, value);
    }

    function transferFrom(IERC20 token, address from, address to, uint256 value) public {
        token.safeTransferFrom(from, to, value);
    }
}

contract Helper is Test {
    Harness executor;
    address recipient = makeAddr("TestHelper: recipient");

    function setUp() public {
        executor = new Harness();
    }
}
