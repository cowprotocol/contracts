// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.8.0 <0.9.0;

contract EventEmitter {
    event Event(uint256 value, uint256 number);

    function emitEvent(uint256 number) external payable {
        emit Event(msg.value, number);
    }
}
