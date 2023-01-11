// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

/// @title Gnosis Protocol v2 Allow List Storage Reader
/// @author Gnosis Developers
contract AllowListStorageReader {
    address private manager;
    mapping(address => bool) private solvers;

    function areSolvers(address[] calldata prospectiveSolvers)
        external
        view
        returns (bool)
    {
        for (uint256 i = 0; i < prospectiveSolvers.length; i++) {
            if (!solvers[prospectiveSolvers[i]]) {
                return false;
            }
        }
        return true;
    }
}
