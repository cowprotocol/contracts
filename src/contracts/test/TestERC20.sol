// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract TestERC20 is ERC20PresetMinterPauser {

    uint8 private _decimals;

    constructor(string memory symbol, uint8 dec)
        ERC20PresetMinterPauser(symbol, symbol)
    {
        _decimals = dec;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
