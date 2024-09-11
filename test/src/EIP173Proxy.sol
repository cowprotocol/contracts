// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.7;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

interface IERC165 {
    function supportsInterface(bytes4 id) external view returns (bool);
}

// ref: https://github.com/wighawag/hardhat-deploy/blob/e0ffcf9e7dc92b246e832c4d175f9dbd8b6df14d/solc_0.8/proxy/EIP173Proxy.sol
contract EIP173Proxy is Proxy {
    bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant OWNER_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == _owner(), "NOT_AUTHORIZED");
        _;
    }

    constructor(address implAddress, address ownerAddress, bytes memory data) {
        _setOwner(ownerAddress);
        _setImplementation(implAddress, data);
    }

    function owner() external view returns (address) {
        return _owner();
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        if (id == 0x01ffc9a7 || id == 0x7f5828d0) {
            return true;
        }
        if (id == 0xFFFFFFFF) {
            return false;
        }

        IERC165 implementation;
        assembly {
            implementation := sload(IMPLEMENTATION_SLOT)
        }

        // Technically this is not standard compliant as ERC-165 require 30,000 gas which that call cannot ensure
        // because it is itself inside `supportsInterface` that might only get 30,000 gas.
        // In practise this is unlikely to be an issue.
        try implementation.supportsInterface(id) returns (bool support) {
            return support;
        } catch {
            return false;
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _setOwner(newOwner);
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        _setImplementation(newImplementation, "");
    }

    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable onlyOwner {
        _setImplementation(newImplementation, data);
    }

    function _owner() internal view returns (address adminAddress) {
        assembly {
            adminAddress := sload(OWNER_SLOT)
        }
    }

    function _setOwner(address newOwner) internal {
        address previousOwner = _owner();
        assembly {
            sstore(OWNER_SLOT, newOwner)
        }
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function _implementation() internal view override returns (address) {
        address impl;
        assembly {
            impl := sload(IMPLEMENTATION_SLOT)
        }
        return impl;
    }

    function _setImplementation(address impl, bytes memory data) internal {
        assembly {
            sstore(IMPLEMENTATION_SLOT, impl)
        }

        if (data.length > 0) {
            (bool success,) = impl.delegatecall(data);
            if (!success) {
                assembly {
                    // This assembly ensure the revert contains the exact string data
                    let returnDataSize := returndatasize()
                    returndatacopy(0, 0, returnDataSize)
                    revert(0, returnDataSize)
                }
            }
        }
    }
}
