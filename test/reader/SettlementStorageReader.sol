// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";
import {GPv2Settlement, IVault, StorageAccessible} from "src/contracts/GPv2Settlement.sol";
import {SettlementStorageReader} from "src/contracts/reader/SettlementStorageReader.sol";

import {Order} from "test/libraries/Order.sol";

contract SettlementStorageReaderTest is Test {
    GPv2Settlement private settlement;
    SettlementStorageReader private reader;

    function setUp() public {
        address authenticator = makeAddr("SettlementStorageReaderTest: authenticator");
        address vault = makeAddr("SettlementStorageReaderTest: vault");
        settlement = new GPv2Settlement(GPv2AllowListAuthentication(authenticator), IVault(vault));

        reader = new SettlementStorageReader();
    }

    function readFilledAmountsForOrders(
        StorageAccessible base,
        SettlementStorageReader storageReader,
        bytes[] memory orderUids
    ) private returns (uint256[] memory) {
        bytes memory result = base.simulateDelegatecall(
            address(storageReader), abi.encodeCall(SettlementStorageReader.filledAmountsForOrders, (orderUids))
        );
        return abi.decode(result, (uint256[]));
    }

    function test_filledAmountsForOrders_returns_expected_fill_amounts() public {
        address trader0 = makeAddr("trader 0");
        address trader1 = makeAddr("trader 1");
        address trader2 = makeAddr("trader 2");
        bytes[] memory orderUid = new bytes[](3);
        orderUid[0] = Order.computeOrderUid(keccak256("order hash 0"), trader0, type(uint32).max);
        orderUid[1] = Order.computeOrderUid(keccak256("order hash 1"), trader1, type(uint32).max);
        orderUid[2] = Order.computeOrderUid(keccak256("order hash 2"), trader2, type(uint32).max);

        uint256[] memory expectedFilledAmounts = new uint256[](3);
        vm.prank(trader0);
        settlement.invalidateOrder(orderUid[0]);
        expectedFilledAmounts[0] = type(uint256).max;
        vm.prank(trader1);
        settlement.invalidateOrder(orderUid[1]);
        expectedFilledAmounts[1] = type(uint256).max;
        // Trader 3 does not invalidate its order
        expectedFilledAmounts[2] = 0;

        uint256[] memory filledAmounts = readFilledAmountsForOrders(settlement, reader, orderUid);
        assertEq(filledAmounts, expectedFilledAmounts);
    }
}
