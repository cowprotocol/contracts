// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract ERC20PresetPermit is ERC20Permit {
    constructor(string memory symbol) ERC20(symbol, symbol) ERC20Permit(symbol) 
    // solhint-disable-next-line no-empty-blocks
    {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
