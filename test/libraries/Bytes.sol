// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

library Bytes {
    function slice(bytes memory d, uint256 offset, uint256 length) internal pure returns (bytes memory) {
        if (d.length < offset + length) {
            revert("Slice out of bounds");
        }

        bytes memory b = new bytes(length);
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            // Copy the data from the source to the destination
            let src := add(add(d, 0x20), offset)
            let dst := add(b, 0x20)
            mcopy(dst, src, length)
        }

        return b;
    }
}
