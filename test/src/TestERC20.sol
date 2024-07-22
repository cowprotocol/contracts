// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol";

contract TestERC20 is ERC20PresetMinterPauser {
    constructor(string memory symbol, uint8 decimals) ERC20PresetMinterPauser(symbol, symbol) {
        _setupDecimals(decimals);
    }
}
