// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

import "../GPv2AllowListAuthentication.sol";

contract GPv2AllowListAuthenticationV2 is GPv2AllowListAuthentication {
    function newMethod() external pure returns (uint256) {
        return 1337;
    }
}
