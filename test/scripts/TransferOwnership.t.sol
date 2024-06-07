// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {TransferOwnership, ERC173} from "src/scripts/TransferOwnership.s.sol";
import {ERC165} from "src/scripts/interfaces/ERC173.sol";
import {GPv2AllowListAuthentication} from "src/contracts/GPv2AllowListAuthentication.sol";

contract TestTransferOwnership is Test {
    TransferOwnership private script;
    ERC173 private proxy;
    GPv2AllowListAuthentication private proxyAsAuthenticator;
    address private owner;

    function setUp() public {
        // It's not possible to use `prank` with a script: "you have an active
        // prank; broadcasting and pranks are not compatible".
        // Since this contract will be the executor of the script, as a
        // workaround we'll make it the owner.
        // This workaround also requires to make `msg.sender` an input to
        // vm.broadcast(), otherwise the broadcaster in the test changes
        // compared to when running the script.
        owner = address(this);

        GPv2AllowListAuthentication impl = new GPv2AllowListAuthentication();
        script = new TransferOwnership();
        address deployed = deployAuthenticatorProxy(owner, address(impl));
        proxy = ERC173(deployed);
        proxyAsAuthenticator = GPv2AllowListAuthentication(deployed);
    }

    function test_transfers_proxy_ownership_and_resets_manager() public {
        address newOwner = makeAddr("TestTransferOwnership: new proxy owner");
        assertEq(proxy.owner(), owner);
        assertEq(proxyAsAuthenticator.manager(), owner);

        TransferOwnership.ScriptParams memory params = TransferOwnership
            .ScriptParams({
                newOwner: newOwner,
                authenticatorProxy: proxy,
                resetManager: true
            });

        script.runWith(params);

        assertEq(proxy.owner(), newOwner, "did not change the owner");
        assertEq(
            proxyAsAuthenticator.manager(),
            newOwner,
            "did not change the manager"
        );
    }

    function test_only_transfers_proxy_ownership() public {
        address newOwner = makeAddr("TestTransferOwnership: new proxy owner");
        assertEq(proxy.owner(), owner);
        assertEq(proxyAsAuthenticator.manager(), owner);

        TransferOwnership.ScriptParams memory params = TransferOwnership
            .ScriptParams({
                newOwner: newOwner,
                authenticatorProxy: proxy,
                resetManager: false
            });

        script.runWith(params);

        assertEq(proxy.owner(), newOwner, "did not change the owner");
        assertEq(proxyAsAuthenticator.manager(), owner, "changed the manager");
    }

    function test_reverts_if_no_proxy_at_target() public {
        address notAProxy = makeAddr("not a proxy");
        TransferOwnership.ScriptParams memory params = TransferOwnership
            .ScriptParams({
                newOwner: makeAddr("some owner"),
                authenticatorProxy: ERC173(notAProxy),
                resetManager: false
            });

        vm.expectRevert(
            bytes(
                string.concat(
                    "No code at target authenticator proxy ",
                    vm.toString(notAProxy),
                    "."
                )
            )
        );
        script.runWith(params);
    }

    function test_reverts_if_proxy_does_not_support_ERC173() public {
        address noERC173Proxy = makeAddr("proxy not supporting ERC173");
        TransferOwnership.ScriptParams memory params = TransferOwnership
            .ScriptParams({
                newOwner: makeAddr("some owner"),
                authenticatorProxy: ERC173(noERC173Proxy),
                resetManager: false
            });
        vm.etch(noERC173Proxy, hex"1337");
        vm.mockCall(
            noERC173Proxy,
            abi.encodeCall(ERC165.supportsInterface, type(ERC173).interfaceId),
            abi.encode(false)
        );

        vm.expectRevert(
            bytes(
                string.concat(
                    "Not a valid proxy contract: target address ",
                    vm.toString(noERC173Proxy),
                    " does not support the ERC173 interface."
                )
            )
        );
        script.runWith(params);
    }

    function test_reverts_if_proxy_reverts_on_supportsInterface() public {
        address revertingProxy = makeAddr(
            "proxy reverting on calls to supportsInterface"
        );
        TransferOwnership.ScriptParams memory params = TransferOwnership
            .ScriptParams({
                newOwner: makeAddr("some owner"),
                authenticatorProxy: ERC173(revertingProxy),
                resetManager: false
            });
        vm.etch(revertingProxy, hex"1337");
        vm.mockCallRevert(
            revertingProxy,
            abi.encodeCall(ERC165.supportsInterface, type(ERC173).interfaceId),
            abi.encode("some revert error")
        );

        vm.expectRevert(
            bytes(
                string.concat(
                    "Not a valid proxy contract: target address ",
                    vm.toString(revertingProxy),
                    " does not support the ERC173 interface."
                )
            )
        );
        script.runWith(params);
    }

    function deployAuthenticatorProxy(
        address targetOwner,
        address implementation
    ) internal returns (address) {
        // We deploy the proxy from bytecode to ensure compatibility with the
        // existing contract setup, currently built with Solidity v0.7.
        // See contract code and constructor arguments at:
        // <https://github.com/wighawag/hardhat-deploy/blob/ddca16832e906fc6f1576dc253cb53df043aad75/solc_0.7/proxy/EIP173Proxy.sol>

        bytes memory deploymentBytecodeWithArgs = abi.encodePacked(
            AUTHENTICATOR_PROXY_DEPLOYMENT_BYTECODE,
            abi.encode(
                implementation,
                targetOwner,
                abi.encodeCall(
                    GPv2AllowListAuthentication.initializeManager,
                    (targetOwner)
                )
            )
        );

        address deployed;
        vm.startPrank(makeAddr("TestTransferOwnership: proxy deployer"));
        assembly {
            deployed := create(
                0,
                add(deploymentBytecodeWithArgs, 0x20),
                mload(deploymentBytecodeWithArgs)
            )
        }
        vm.stopPrank();

        if (deployed == address(0)) {
            revert("Error on proxy deployment");
        }
        return deployed;
    }
}

// From <https://etherscan.io/address/0x2c4c28ddbdac9c5e7055b4c863b72ea0149d8afe>
bytes constant AUTHENTICATOR_PROXY_DEPLOYMENT_BYTECODE = hex"6080604052604051610bed380380610bed8339818101604052606081101561002657600080fd5b8151602083015160408085018051915193959294830192918464010000000082111561005157600080fd5b90830190602082018581111561006657600080fd5b825164010000000081118282018810171561008057600080fd5b82525081516020918201929091019080838360005b838110156100ad578181015183820152602001610095565b50505050905090810190601f1680156100da5780820380516001836020036101000a031916815260200191505b506040525050506100f1838261010260201b60201c565b6100fa82610225565b505050610299565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc8054908390556040516001600160a01b0380851691908316907f5570d70a002632a7b0b3c9304cc89efb62d8da9eca0dbd7752c83b737906829690600090a3815115610220576000836001600160a01b0316836040518082805190602001908083835b602083106101a55780518252601f199092019160209182019101610186565b6001836020036101000a038019825116818451168082178552505050505050905001915050600060405180830381855af49150503d8060008114610205576040519150601f19603f3d011682016040523d82523d6000602084013e61020a565b606091505b505090508061021e573d806000803e806000fd5b505b505050565b600061022f610286565b905081600080516020610bcd83398151915255816001600160a01b0316816001600160a01b03167f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e060405160405180910390a35050565b600080516020610bcd8339815191525490565b610925806102a86000396000f3fe60806040526004361061005e5760003560e01c80634f1ef286116100435780634f1ef286146101745780638da5cb5b14610201578063f2fde38b1461023f576100ca565b806301ffc9a7146100d45780633659cfe614610134576100ca565b366100ca57604080517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152600e60248201527f45544845525f52454a4543544544000000000000000000000000000000000000604482015290519081900360640190fd5b6100d261027f565b005b3480156100e057600080fd5b50610120600480360360208110156100f757600080fd5b50357fffffffff00000000000000000000000000000000000000000000000000000000166102ca565b604080519115158252519081900360200190f35b34801561014057600080fd5b506100d26004803603602081101561015757600080fd5b503573ffffffffffffffffffffffffffffffffffffffff1661048d565b6100d26004803603604081101561018a57600080fd5b73ffffffffffffffffffffffffffffffffffffffff82351691908101906040810160208201356401000000008111156101c257600080fd5b8201836020820111156101d457600080fd5b803590602001918460018302840111640100000000831117156101f657600080fd5b50909250905061054a565b34801561020d57600080fd5b50610216610630565b6040805173ffffffffffffffffffffffffffffffffffffffff9092168252519081900360200190f35b34801561024b57600080fd5b506100d26004803603602081101561026257600080fd5b503573ffffffffffffffffffffffffffffffffffffffff1661063f565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5460003681823780813683855af491503d8082833e8280156102c0578183f35b8183fd5b50505050565b60007f01ffc9a7000000000000000000000000000000000000000000000000000000007fffffffff000000000000000000000000000000000000000000000000000000008316148061035d57507f7f5828d0000000000000000000000000000000000000000000000000000000007fffffffff000000000000000000000000000000000000000000000000000000008316145b1561036a57506001610488565b7fffffffff00000000000000000000000000000000000000000000000000000000808316141561039c57506000610488565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc54604080517f01ffc9a70000000000000000000000000000000000000000000000000000000081527fffffffff0000000000000000000000000000000000000000000000000000000085166004820152905173ffffffffffffffffffffffffffffffffffffffff8316916301ffc9a7916024808301926020929190829003018186803b15801561044c57600080fd5b505afa92505050801561047157506040513d602081101561046c57600080fd5b505160015b61047f576000915050610488565b91506104889050565b919050565b6104956106e9565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff161461052e57604080517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152600e60248201527f4e4f545f415554484f52495a4544000000000000000000000000000000000000604482015290519081900360640190fd5b610547816040518060200160405280600081525061070e565b50565b6105526106e9565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16146105eb57604080517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152600e60248201527f4e4f545f415554484f52495a4544000000000000000000000000000000000000604482015290519081900360640190fd5b61062b8383838080601f01602080910402602001604051908101604052809392919081815260200183838082843760009201919091525061070e92505050565b505050565b600061063a6106e9565b905090565b6106476106e9565b73ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff16146106e057604080517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152600e60248201527f4e4f545f415554484f52495a4544000000000000000000000000000000000000604482015290519081900360640190fd5b61054781610862565b7fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035490565b7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80549083905560405173ffffffffffffffffffffffffffffffffffffffff80851691908316907f5570d70a002632a7b0b3c9304cc89efb62d8da9eca0dbd7752c83b737906829690600090a381511561062b5760008373ffffffffffffffffffffffffffffffffffffffff16836040518082805190602001908083835b602083106107e957805182527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe090920191602091820191016107ac565b6001836020036101000a038019825116818451168082178552505050505050905001915050600060405180830381855af49150503d8060008114610849576040519150601f19603f3d011682016040523d82523d6000602084013e61084e565b606091505b50509050806102c4573d806000803e806000fd5b600061086c6106e9565b9050817fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103558173ffffffffffffffffffffffffffffffffffffffff168173ffffffffffffffffffffffffffffffffffffffff167f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e060405160405180910390a3505056fea26469706673582212209a21f7e39c677b08222e0075630be7fe375e2d2b64ed95bb001fbeae13a76b5a64736f6c63430007060033b53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
