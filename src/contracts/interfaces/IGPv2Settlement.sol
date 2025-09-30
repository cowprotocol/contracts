// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "./IERC20.sol";
import "./GPv2Authentication.sol";
import "./IVault.sol";
import "../libraries/GPv2Trade.sol";
import "../libraries/GPv2Interaction.sol";

/// @title Gnosis Protocol v2 Settlement Interface
/// @author Gnosis Developers
interface IGPv2Settlement {
    /// @dev Event emitted for each executed trade.
    event Trade(
        address indexed owner,
        IERC20 sellToken,
        IERC20 buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 feeAmount,
        bytes orderUid
    );

    /// @dev Event emitted for each executed interaction.
    ///
    /// For gas efficiency, only the interaction calldata selector (first 4
    /// bytes) is included in the event. For interactions without calldata or
    /// whose calldata is shorter than 4 bytes, the selector will be `0`.
    event Interaction(address indexed target, uint256 value, bytes4 selector);

    /// @dev Event emitted when a settlement completes
    event Settlement(address indexed solver);

    /// @dev Event emitted when an order is invalidated.
    event OrderInvalidated(address indexed owner, bytes orderUid);

    /// @dev The authenticator is used to determine who can call the settle function.
    /// That is, only authorized solvers have the ability to invoke settlements.
    /// Any valid authenticator implements an isSolver method called by the onlySolver
    /// modifier below.
    function authenticator() external view returns (GPv2Authentication);

    /// @dev The Balancer Vault the protocol used for managing user funds.
    function vault() external view returns (IVault);

    /// @dev Map each user order by UID to the amount that has been filled so
    /// far. If this amount is larger than or equal to the amount traded in the
    /// order (amount sold for sell orders, amount bought for buy orders) then
    /// the order cannot be traded anymore. If the order is fill or kill, then
    /// this value is only used to determine whether the order has already been
    /// executed.
    function filledAmount(bytes calldata orderUid) external view returns (uint256);

    /// @dev Settle the specified orders at a clearing price. Note that it is
    /// the responsibility of the caller to ensure that all GPv2 invariants are
    /// upheld for the input settlement, otherwise this call will revert.
    /// Namely:
    /// - All orders are valid and signed
    /// - Accounts have sufficient balance and approval.
    /// - Settlement contract has sufficient balance to execute trades. Note
    ///   this implies that the accumulated fees held in the contract can also
    ///   be used for settlement. This is OK since:
    ///   - Solvers need to be authorized
    ///   - Misbehaving solvers will be slashed for abusing accumulated fees for
    ///     settlement
    ///   - Critically, user orders are entirely protected
    ///
    /// @param tokens An array of ERC20 tokens to be traded in the settlement.
    /// Trades encode tokens as indices into this array.
    /// @param clearingPrices An array of clearing prices where the `i`-th price
    /// is for the `i`-th token in the [`tokens`] array.
    /// @param trades Trades for signed orders.
    /// @param interactions Smart contract interactions split into three
    /// separate lists to be run before the settlement, during the settlement
    /// and after the settlement respectively.
    function settle(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions
    ) external;

    /// @dev Settle an order directly against Balancer V2 pools.
    ///
    /// @param swaps The Balancer V2 swap steps to use for trading.
    /// @param tokens An array of ERC20 tokens to be traded in the settlement.
    /// Swaps and the trade encode tokens as indices into this array.
    /// @param trade The trade to match directly against Balancer liquidity. The
    /// order will always be fully executed, so the trade's `executedAmount`
    /// field is used to represent a swap limit amount.
    function swap(
        IVault.BatchSwapStep[] calldata swaps,
        IERC20[] calldata tokens,
        GPv2Trade.Data calldata trade
    ) external;

    /// @dev Invalidate onchain an order that has been signed offline.
    ///
    /// @param orderUid The unique identifier of the order that is to be made
    /// invalid after calling this function. The user that created the order
    /// must be the sender of this message. See [`extractOrderUidParams`]
    /// for details on orderUid.
    function invalidateOrder(bytes calldata orderUid) external;

    /// @dev Free storage from the filled amounts of **expired** orders to claim
    /// a gas refund. This method can only be called as an interaction.
    ///
    /// @param orderUids The unique identifiers of the expired order to free
    /// storage for.
    function freeFilledAmountStorage(bytes[] calldata orderUids) external;

    /// @dev Free storage from the pre signatures of **expired** orders to claim
    /// a gas refund. This method can only be called as an interaction.
    ///
    /// @param orderUids The unique identifiers of the expired order to free
    /// storage for.
    function freePreSignatureStorage(bytes[] calldata orderUids) external;
}