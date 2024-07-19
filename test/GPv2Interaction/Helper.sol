// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2Interaction} from "src/contracts/libraries/GPv2Interaction.sol";

contract Harness {
    function executeTest(GPv2Interaction.Data calldata interaction) external {
        GPv2Interaction.execute(interaction);
    }

    function selectorTest(GPv2Interaction.Data calldata interaction) external pure returns (bytes4) {
        return GPv2Interaction.selector(interaction);
    }
}

contract Helper is Test {
    Harness executor;
    address recipient = makeAddr("TestHelper: recipient");

    function setUp() public {
        executor = new Harness();
    }
}
