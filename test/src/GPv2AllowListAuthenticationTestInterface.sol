// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.7.6 <0.9.0;

import "src/contracts/GPv2AllowListAuthentication.sol";
import "src/contracts/libraries/GPv2EIP1967.sol";

contract GPv2AllowListAuthenticationTestInterface is
    GPv2AllowListAuthentication
{
    constructor(address owner) {
        GPv2EIP1967.setAdmin(owner);
    }
}
