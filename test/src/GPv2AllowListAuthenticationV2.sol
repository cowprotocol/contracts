// SPDX-License-Identifier: LGPL-3.0-or-later
// solhint-disable-next-line compiler-version
pragma solidity >=0.7.6 <0.9.0;

import "src/contracts/GPv2AllowListAuthentication.sol";

contract GPv2AllowListAuthenticationV2 is GPv2AllowListAuthentication {
    function newMethod() external pure returns (uint256) {
        return 1337;
    }
}
