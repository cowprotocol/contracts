// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Base, Helper} from "../Helper.sol";

import {Settlement} from "../helpers/Settlement.sol";

// solhint-disable func-name-mixedcase
contract Settle is Helper, Settlement {
    function setUp() public override(Base, Helper) {
        super.setUp();
    }

    function test_rejects_transactions_from_non_solvers() public {
        vm.expectRevert("GPv2: not a solver");
        settle(encode());
    }
}
