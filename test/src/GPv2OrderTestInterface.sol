// SPDX-License-Identifier: LGPL-3.0-or-later
// solhint-disable-next-line compiler-version
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "src/contracts/libraries/GPv2Order.sol";

contract GPv2OrderTestInterface {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    function typeHashTest() external pure returns (bytes32) {
        return GPv2Order.TYPE_HASH;
    }

    function hashTest(GPv2Order.Data memory order, bytes32 domainSeparator)
        external
        pure
        returns (bytes32 orderDigest)
    {
        orderDigest = order.hash(domainSeparator);
    }

    function packOrderUidParamsTest(uint256 bufferLength, bytes32 orderDigest, address owner, uint32 validTo)
        external
        pure
        returns (bytes memory orderUid)
    {
        orderUid = new bytes(bufferLength);
        orderUid.packOrderUidParams(orderDigest, owner, validTo);
    }

    function extractOrderUidParamsTest(bytes calldata orderUid)
        external
        pure
        returns (bytes32 orderDigest, address owner, uint32 validTo)
    {
        return orderUid.extractOrderUidParams();
    }
}
