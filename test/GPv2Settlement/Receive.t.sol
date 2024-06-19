// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {GPv2Order} from "src/contracts/libraries/GPv2Order.sol";

import {Helper} from "./Helper.sol";

// solhint-disable func-name-mixedcase
contract Receive is Helper {
    using GPv2Order for bytes;

    function test_allows_receiving_ether_directly_in_settlement_contract() public {
        uint256 balance = address(settlement).balance;
        assertEq(balance, 0);
        (bool success,) = address(settlement).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(settlement).balance, 1 ether);
    }
}
