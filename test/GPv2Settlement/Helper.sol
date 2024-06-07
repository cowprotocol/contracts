// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {
    IVault,
    GPv2Authentication,
    GPv2Settlement,
    GPv2Trade,
    GPv2Interaction,
    GPv2Transfer,
    IERC20
} from "src/contracts/GPv2Settlement.sol";

import {IVault, GPv2Authentication} from "src/contracts/GPv2Settlement.sol";
import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

abstract contract Helper is Test {
    using stdJson for string;

    GPv2Authentication internal authenticator;
    IVault internal vault;

    Harness internal settlement;
    bytes32 internal domainSeparator;

    Vm.Wallet internal solver;
    Vm.Wallet internal trader;

    function setUp() public virtual {
        // Configure addresses
        address deployer = makeAddr("deployer");
        address owner = makeAddr("owner");
        vm.startPrank(deployer);

        // Deploy the allowlist manager
        GPv2AllowListAuthentication allowList = new GPv2AllowListAuthentication();
        allowList.initializeManager(owner);
        authenticator = allowList;

        // Deploy the vault contract
        vault = deployBalancerVault();

        // Deploy the settlement contract
        settlement = new Harness(authenticator, vault);

        // Reset the prank
        vm.stopPrank();

        // Set the domain separator
        domainSeparator = settlement.domainSeparator();

        // Create wallets
        solver = vm.createWallet("solver");
        trader = vm.createWallet("trader");
    }

    function deployBalancerVault() private returns (IVault vault_) {
        string memory path = string.concat(vm.projectRoot(), "/", "balancer/Vault.json");
        string memory json = vm.readFile(path);
        bytes memory bytecode = json.parseRaw(".bytecode");

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            vault_ := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}

contract Harness is GPv2Settlement {
    constructor(GPv2Authentication authenticator_, IVault vault) GPv2Settlement(authenticator_, vault) {}

    function setFilledAmount(bytes calldata orderUid, uint256 amount) external {
        filledAmount[orderUid] = amount;
    }

    function computeTradeExecutionsTest(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades
    ) external returns (GPv2Transfer.Data[] memory inTransfers, GPv2Transfer.Data[] memory outTransfers) {
        (inTransfers, outTransfers) = computeTradeExecutions(tokens, clearingPrices, trades);
    }

    function computeTradeExecutionMemoryTest() external returns (uint256 mem) {
        RecoveredOrder memory recoveredOrder;
        GPv2Transfer.Data memory inTransfer;
        GPv2Transfer.Data memory outTransfer;

        // NOTE: Solidity stores the free memory pointer at address 0x40. Read
        // it before and after calling `processOrder` to ensure that there are
        // no memory allocations.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mem := mload(0x40)
        }

        recoveredOrder.data.validTo = uint32(block.timestamp);
        computeTradeExecution(recoveredOrder, 1, 1, 0, inTransfer, outTransfer);

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mem := sub(mload(0x40), mem)
        }
    }

    function executeInteractionsTest(GPv2Interaction.Data[] calldata interactions) external {
        executeInteractions(interactions);
    }

    function freeFilledAmountStorageTest(bytes[] calldata orderUids) external {
        this.freeFilledAmountStorage(orderUids);
    }

    function freePreSignatureStorageTest(bytes[] calldata orderUids) external {
        this.freePreSignatureStorage(orderUids);
    }
}
