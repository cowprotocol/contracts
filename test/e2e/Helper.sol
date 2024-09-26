// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm, stdJson} from "forge-std/Test.sol";
import {IERC20} from "src/contracts/interfaces/IERC20.sol";

import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";
import {
    GPv2Authentication,
    GPv2Interaction,
    GPv2Settlement,
    GPv2Trade,
    IERC20,
    IVault
} from "src/contracts/GPv2Settlement.sol";

import {WETH9} from "./WETH9.sol";
import {SettlementEncoder} from "test/libraries/encoders/SettlementEncoder.sol";
import {SwapEncoder} from "test/libraries/encoders/SwapEncoder.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

interface IAuthorizer {
    function grantRole(bytes32, address) external;
}

interface IERC20Mintable is IERC20 {
    function mint(address, uint256) external;
    function burn(uint256) external;
}

// solhint-disable func-name-mixedcase
// solhint-disable max-states-count
abstract contract Helper is Test {
    using stdJson for string;
    using SettlementEncoder for SettlementEncoder.State;

    address internal deployer;
    address internal owner;
    GPv2Settlement internal settlement;
    bytes32 internal domainSeparator;
    GPv2Authentication internal authenticator;
    IVault internal vault;
    GPv2AllowListAuthentication internal allowList;
    GPv2AllowListAuthentication internal allowListImpl;
    address vaultRelayer;
    address balancerVaultAuthorizer;

    SettlementEncoder.State internal encoder;
    SwapEncoder.State internal swapEncoder;

    address internal solver;
    Vm.Wallet internal trader;

    bool immutable isForked;
    uint256 forkId;

    WETH9 weth;

    bytes32 constant SALT = "Mattresses in Berlin!";

    constructor(bool _isForked) {
        isForked = _isForked;
    }

    function setUp() public virtual {
        if (isForked) {
            uint256 blockNumber = vm.envUint("FORK_BLOCK_NUMBER");
            string memory forkUrl = "https://eth.llamarpc.com";

            try vm.envString("FORK_URL") returns (string memory url) {
                forkUrl = url;
            } catch {}

            forkId = vm.createSelectFork(forkUrl, blockNumber);
            weth = WETH9(payable(WETH));
        } else {
            weth = new WETH9();
        }

        // Configure addresses
        deployer = makeAddr("E2E.Helper: deployer");
        owner = makeAddr("E2E.Helper: owner");
        solver = makeAddr("E2E.Helper: solver");
        vm.startPrank(deployer);

        // Deploy the allowlist manager
        allowListImpl = new GPv2AllowListAuthentication{salt: SALT}();
        allowList = GPv2AllowListAuthentication(
            deployProxy(address(allowListImpl), owner, abi.encodeCall(allowListImpl.initializeManager, (owner)), SALT)
        );
        authenticator = allowList;

        (balancerVaultAuthorizer, vault) = _deployBalancerVault();

        // Deploy the settlement contract
        settlement = new GPv2Settlement{salt: SALT}(authenticator, vault);
        vaultRelayer = address(settlement.vaultRelayer());

        // Reset the prank
        vm.stopPrank();

        _grantBalancerRolesToRelayer(balancerVaultAuthorizer, address(vault), vaultRelayer);

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

    function _deployBalancerVault() internal returns (address, IVault) {
        bytes memory authorizerInitCode = abi.encodePacked(_getBalancerBytecode("Authorizer"), abi.encode(owner));
        address authorizer = _create(authorizerInitCode, 0);

        bytes memory vaultInitCode =
            abi.encodePacked(_getBalancerBytecode("Vault"), abi.encode(authorizer, address(weth), 0, 0));
        address deployedVault = _create(vaultInitCode, 0);

        return (authorizer, IVault(deployedVault));
    }

    function _grantBalancerRolesToRelayer(address authorizer, address deployedVault, address relayer) internal {
        _grantBalancerActionRole(
            authorizer, deployedVault, relayer, "manageUserBalance((uint8,address,uint256,address,address)[])"
        );
        _grantBalancerActionRole(
            authorizer,
            deployedVault,
            relayer,
            "batchSwap(uint8,(bytes32,uint256,uint256,uint256,bytes)[],address[],(address,bool,address,bool),int256[],uint256)"
        );
    }

    function _grantBalancerActionRole(address authorizer, address balVault, address to, string memory action)
        internal
    {
        vm.prank(owner);
        IAuthorizer(authorizer).grantRole(_getActionId(action, balVault), to);
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
        require(deployed != address(0), "deployment failed");
    }

    function _create2(bytes memory initCode, uint256 value, bytes32 salt) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(value, add(initCode, 0x20), mload(initCode), salt)
        }
        require(deployed != address(0), "deployment failed");
    }

    function deployMintableErc20(string memory name, string memory symbol) internal returns (IERC20Mintable token) {
        // need to use like this because OZ requires ^0.7 and tests are on ^0.8
        bytes memory initCode = abi.encodePacked(vm.getCode("ERC20Mintable"), abi.encode(name, symbol));
        token = IERC20Mintable(_create(initCode, 0));
    }

    function deployProxy(address implAddress, address ownerAddress, bytes memory data, bytes32 salt)
        internal
        returns (address proxy)
    {
        proxy =
            _create2(abi.encodePacked(vm.getCode("EIP173Proxy"), abi.encode(implAddress, ownerAddress, data)), 0, salt);
    }
}
