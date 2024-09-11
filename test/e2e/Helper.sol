// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm, stdJson} from "forge-std/Test.sol";

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";
import {
    GPv2Authentication,
    GPv2Interaction,
    GPv2Settlement,
    GPv2Trade,
    GPv2Transfer,
    IERC20,
    IVault
} from "src/contracts/GPv2Settlement.sol";

import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";
import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";

address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

interface IAuthorizer {
    function grantRole(bytes32, address) external;
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

// solhint-disable func-name-mixedcase
abstract contract Helper is Test {
    using stdJson for string;
    using SettlementEncoder for SettlementEncoder.State;

    address internal deployer;
    address internal owner;
    Harness internal settlement;
    bytes32 internal domainSeparator;
    GPv2Authentication internal authenticator;
    IVault internal vault;
    GPv2AllowListAuthentication internal allowList;
    address vaultRelayer;

    SettlementEncoder.State internal encoder;
    SwapEncoder.State internal swapEncoder;

    address internal solver;
    Vm.Wallet internal trader;

    bool immutable isForked;
    uint256 forkId;

    constructor(bool _isForked) {
        isForked = _isForked;
    }

    function setUp() public virtual {
        if (isForked) {
            uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER");
            string memory forkUrl = vm.envString("FORK_URL");
            forkId = vm.createSelectFork(forkUrl, blockNumber);
        }

        // Configure addresses
        deployer = makeAddr("E2E.Helper: deployer");
        owner = makeAddr("E2E.Helper: owner");
        solver = makeAddr("E2E.Helper: solver");
        vm.startPrank(deployer);

        // Deploy the allowlist manager
        allowList = new GPv2AllowListAuthentication();
        allowList.initializeManager(owner);
        authenticator = allowList;

        // use production deployment if forked base
        if (isForked) {
            vault = IVault(BALANCER_VAULT);
        }
        // deploy balancer vault if not forked
        else {
            _deployBalancerVaultAt(address(vault));
        }

        vault = IVault(makeAddr("E2E.Helper: vault"));
        vm.mockCallRevert(address(vault), hex"", "unexpected call to mock vault");

        // Deploy the settlement contract
        settlement = new Harness(authenticator, vault);
        vaultRelayer = address(settlement.vaultRelayer());

        // Reset the prank
        vm.stopPrank();

        // By default, allow `solver` to settle
        vm.prank(owner);
        allowList.addSolver(solver);

        // Configure default encoders
        encoder = SettlementEncoder.makeSettlementEncoder();
        swapEncoder = SwapEncoder.makeSwapEncoder();

        // Set the domain separator
        domainSeparator = settlement.domainSeparator();

        // Create wallets
        trader = vm.createWallet("E2E.Helper: trader");
    }

    function settle(SettlementEncoder.EncodedSettlement memory _settlement) internal {
        settlement.settle(_settlement.tokens, _settlement.clearingPrices, _settlement.trades, _settlement.interactions);
    }

    function swap(SwapEncoder.EncodedSwap memory _swap) internal {
        settlement.swap(_swap.swaps, _swap.tokens, _swap.trade);
    }

    function emptySettlement() internal pure returns (SettlementEncoder.EncodedSettlement memory) {
        return SettlementEncoder.EncodedSettlement({
            tokens: new IERC20[](0),
            clearingPrices: new uint256[](0),
            trades: new GPv2Trade.Data[](0),
            interactions: [new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0)]
        });
    }

    function _deployBalancerVaultAt(address _vault) internal {
        bytes memory authorizerInitCode = abi.encodePacked(_getBalancerBytecode("Authorizer"), abi.encode(owner));
        address authorizer = _create(authorizerInitCode, 0);

        bytes memory vaultInitCode = abi.encodePacked(_getBalancerBytecode("Vault"), abi.encode(authorizer, WETH, 0, 0));
        vm.record();
        address deployedVault = _create(vaultInitCode, 0);
        (, bytes32[] memory writeSlots) = vm.accesses(deployedVault);

        // replay storage writes made in the constructor and set the balancer code
        vm.etch(address(_vault), deployedVault.code);
        for (uint256 i = 0; i < writeSlots.length; i++) {
            bytes32 slot = writeSlots[i];
            bytes32 val = vm.load(deployedVault, slot);
            vm.store(address(_vault), slot, val);
        }

        // grant required roles
        vm.startPrank(owner);
        IAuthorizer(authorizer).grantRole(
            _getActionId("manageUserBalance((uint8,address,uint256,address,address)[])", address(deployedVault)),
            vaultRelayer
        );
        IAuthorizer(authorizer).grantRole(
            _getActionId(
                "batchSwap(uint8,(bytes32,uint256,uint256,uint256,bytes)[],address[],(address,bool,address,bool),int256[],uint256)",
                address(deployedVault)
            ),
            vaultRelayer
        );
        vm.stopPrank();
    }

    function _getActionId(string memory fnDef, address vaultAddr) internal pure returns (bytes32) {
        bytes32 hash = keccak256(bytes(fnDef));
        bytes4 selector = bytes4(hash);
        return keccak256(abi.encodePacked(uint256(uint160(vaultAddr)), selector));
    }

    function _getBalancerBytecode(string memory artifactName) internal view returns (bytes memory) {
        string memory data = vm.readFile(string(abi.encodePacked("balancer/", artifactName, ".json")));
        return vm.parseJsonBytes(data, ".bytecode");
    }

    function _create(bytes memory initCode, uint256 value) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(value, add(initCode, 0x20), mload(initCode))
        }
    }
}
