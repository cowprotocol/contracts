import type { Interaction } from "../interaction";
import type { NormalizedOrder, OrderFlags } from "../order";
import { OrderBalance, OrderKind } from "./order";
import { SigningScheme } from "./signing";

/**
 * The stage an interaction should be executed in.
 */

export enum InteractionStage {
	/**
	 * A pre-settlement intraction.
	 *
	 * The interaction will be executed before any trading occurs. This can be
	 * used, for example, to perform as EIP-2612 `permit` call for a user trading
	 * in the current settlement.
	 */
	PRE = 0,
	/**
	 * An intra-settlement interaction.
	 *
	 * The interaction will be executed after all trade sell amounts are
	 * transferred into the settlement contract, but before the buy amounts are
	 * transferred out to the traders. This can be used, for example, to interact
	 * with on-chain AMMs.
	 */
	INTRA = 1,
	/**
	 * A post-settlement interaction.
	 *
	 * The interaction will be executed after all trading has completed.
	 */
	POST = 2,
}
/**
 * Gnosis Protocol v2 trade flags.
 */

export interface TradeFlags extends OrderFlags {
	/**
	 * The signing scheme used to encode the signature.
	 */
	signingScheme: SigningScheme;
}
/**
 * Trade parameters used in a settlement.
 */

export type Trade = TradeExecution &
	Omit<
		NormalizedOrder,
		| "sellToken"
		| "buyToken"
		| "kind"
		| "partiallyFillable"
		| "sellTokenBalance"
		| "buyTokenBalance"
	> & {
		/**
		 * The index of the sell token in the settlement.
		 */
		sellTokenIndex: bigint;
		/**
		 * The index of the buy token in the settlement.
		 */
		buyTokenIndex: bigint;
		/**
		 * Encoded order flags.
		 */
		flags: bigint;
		/**
		 * Signature data.
		 */
		signature: string | ArrayLike<number>;
	};
/**
 * Details representing how an order was executed.
 */

export interface TradeExecution {
	/**
	 * The executed trade amount.
	 *
	 * How this amount is used by the settlement contract depends on the order
	 * flags:
	 * - Partially fillable sell orders: the amount of sell tokens to trade.
	 * - Partially fillable buy orders: the amount of buy tokens to trade.
	 * - Fill-or-kill orders: this value is ignored.
	 */
	executedAmount: bigint;
}
/**
 * Order refund data.
 *
 * Note: after the London hardfork (specifically the introduction of EIP-3529)
 * order refunds have become meaningless as the refunded amount is less than the
 * gas cost of triggering the refund. The logic surrounding this feature is kept
 * in order to keep full test coverage and in case the value of a refund will be
 * increased again in the future. However, order refunds should not be used in
 * an actual settlement.
 */

export interface OrderRefunds {
	/** Refund storage used for order filled amount */
	filledAmounts: (string | ArrayLike<number>)[];
	/** Refund storage used for order pre-signature */
	preSignatures: (string | ArrayLike<number>)[];
}
/**
 * Table mapping token addresses to their respective clearing prices.
 */

export type Prices = Record<string, bigint | undefined>;
/**
 * Encoded settlement parameters.
 */

export type EncodedSettlement = [
	/** Tokens. */
	string[],
	/** Clearing prices. */
	bigint[],
	/** Encoded trades. */
	Trade[],
	/** Encoded interactions. */
	[Interaction[], Interaction[], Interaction[]],
];
/**
 * An object listing all flag options in order along with their bit offset.
 */

export const FLAG_MASKS = {
	kind: {
		offset: 0,
		options: [OrderKind.SELL, OrderKind.BUY],
	},
	partiallyFillable: {
		offset: 1,
		options: [false, true],
	},
	sellTokenBalance: {
		offset: 2,
		options: [
			OrderBalance.ERC20,
			undefined,
			OrderBalance.EXTERNAL,
			OrderBalance.INTERNAL,
		],
	},
	buyTokenBalance: {
		offset: 4,
		options: [OrderBalance.ERC20, OrderBalance.INTERNAL],
	},
	signingScheme: {
		offset: 5,
		options: [
			SigningScheme.EIP712,
			SigningScheme.ETHSIGN,
			SigningScheme.EIP1271,
			SigningScheme.PRESIGN,
		],
	},
} as const;

export type FlagKey = keyof typeof FLAG_MASKS;
export type FlagOptions<K extends FlagKey> = (typeof FLAG_MASKS)[K]["options"];
export type FlagValue<K extends FlagKey> = Exclude<
	FlagOptions<K>[number],
	undefined
>;
