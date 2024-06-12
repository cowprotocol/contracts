// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Settlement} from "../helpers/Settlement.sol";
import {Swap} from "../helpers/Swap.sol";

// solhint-disable func-name-mixedcase
contract Settle is Settlement, Swap {
    function test_rejects_transactions_from_non_solvers() public {
        vm.expectRevert("GPv2: not a solver");
        settle(encode());
    }
}
