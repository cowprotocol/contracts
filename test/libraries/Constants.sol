// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20, GPv2Order} from "src/contracts/libraries/GPv2Order.sol";
import {GPv2Signing, Sign} from "test/libraries/Sign.sol";

abstract contract Constants {
    // solhint-disable-next-line var-name-mixedcase
    GPv2Order.Data public EMPTY_ORDER = GPv2Order.Data({
        sellToken: IERC20(address(0)),
        buyToken: IERC20(address(0)),
        receiver: address(0),
        sellAmount: 0,
        buyAmount: 0,
        validTo: 0,
        appData: bytes32(0),
        feeAmount: 0,
        kind: GPv2Order.KIND_SELL,
        partiallyFillable: false,
        sellTokenBalance: GPv2Order.BALANCE_ERC20,
        buyTokenBalance: GPv2Order.BALANCE_ERC20
    });

    // solhint-disable-next-line var-name-mixedcase
    Sign.Signature public EMPTY_SIGNATURE = Sign.Signature({scheme: GPv2Signing.Scheme.Eip712, data: new bytes(65)});
}
