import type { SignatureData } from "./core";
import type { SigningScheme } from "./signing";

/**
 * Order kind.
 */
export enum OrderKind {
	/**
	 * A sell order.
	 */
	SELL = "sell",
	/**
	 * A buy order.
	 */
	BUY = "buy",
}

/**
 * Order balance configuration.
 */
export enum OrderBalance {
	/**
	 * Use ERC20 token balances.
	 */
	ERC20 = "erc20",
	/**
	 * Use Balancer Vault external balances.
	 *
	 * This can only be specified specified for the sell balance and allows orders
	 * to re-use Vault ERC20 allowances. When specified for the buy balance, it
	 * will be treated as {@link OrderBalance.ERC20}.
	 */
	EXTERNAL = "external",
	/**
	 * Use Balancer Vault internal balances.
	 */
	INTERNAL = "internal",
}

/**
 * A timestamp value.
 */
export type Timestamp = number | Date;

/**
 * Gnosis Protocol v2 order data.
 */
export interface Order {
	/**
	 * Sell token address.
	 */
	sellToken: string;
	/**
	 * Buy token address.
	 */
	buyToken: string;
	/**
	 * An optional address to receive the proceeds of the trade instead of the
	 * owner (i.e. the order signer).
	 */
	receiver?: string;
	/**
	 * The order sell amount.
	 *
	 * For fill or kill sell orders, this amount represents the exact sell amount
	 * that will be executed in the trade. For fill or kill buy orders, this
	 * amount represents the maximum sell amount that can be executed. For partial
	 * fill orders, this represents a component of the limit price fraction.
	 */
	sellAmount: bigint;
	/**
	 * The order buy amount.
	 *
	 * For fill or kill sell orders, this amount represents the minimum buy amount
	 * that can be executed in the trade. For fill or kill buy orders, this amount
	 * represents the exact buy amount that will be executed. For partial fill
	 * orders, this represents a component of the limit price fraction.
	 */
	buyAmount: bigint;
	/**
	 * The timestamp this order is valid until
	 */
	validTo: Timestamp;
	/**
	 * Arbitrary application specific data that can be added to an order. This can
	 * also be used to ensure uniqueness between two orders with otherwise the
	 * exact same parameters.
	 */
	appData: `0x${string}` | ArrayLike<number>;
	/**
	 * Fee to give to the protocol.
	 */
	feeAmount: bigint;
	/**
	 * The order kind.
	 */
	kind: OrderKind;
	/**
	 * Specifies whether or not the order is partially fillable.
	 */
	partiallyFillable: boolean;
	/**
	 * Specifies how the sell token balance will be withdrawn. It can either be
	 * taken using ERC20 token allowances made directly to the Vault relayer
	 * (default) or using Balancer Vault internal or external balances.
	 */
	sellTokenBalance?: OrderBalance;
	/**
	 * Specifies how the buy token balance will be paid. It can either be paid
	 * directly in ERC20 tokens (default) in Balancer Vault internal balances.
	 */
	buyTokenBalance?: OrderBalance;
}

export interface OrderSignature {
	scheme: SigningScheme;
	data: string | SignatureData;
}
