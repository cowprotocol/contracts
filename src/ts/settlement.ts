import type { EthereumClientAdapter } from "./adapters/ethereum-client-adapter";
import { ORDER_TYPE_FIELDS } from "./constants";
import {
	type Interaction,
	type InteractionLike,
	normalizeInteraction,
} from "./interaction";
import {
	type NormalizedOrder,
	ORDER_UID_LENGTH,
	type OrderFlags,
	normalizeBuyTokenBalance,
	normalizeOrder,
} from "./order";
import type { EcdsaSigningScheme, Signature } from "./sign";
import type { TypedDataDomain } from "./types/core";
import { type Order, OrderBalance, OrderKind } from "./types/order";
import { SigningScheme } from "./types/signing";
import type { SignerContext } from "./types/signing";

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
		sellTokenIndex: number | bigint | string;
		/**
		 * The index of the buy token in the settlement.
		 */
		buyTokenIndex: number | bigint | string;
		/**
		 * Encoded order flags.
		 */
		flags: number | bigint | string;
		/**
		 * Signature data.
		 */
		signature: string;
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
	executedAmount: number | bigint | string;
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
	filledAmounts: string[];
	/** Refund storage used for order pre-signature */
	preSignatures: string[];
}

/**
 * Table mapping token addresses to their respective clearing prices.
 */
export type Prices = Record<string, number | bigint | string | undefined>;

/**
 * Encoded settlement parameters.
 */
export type EncodedSettlement = [
	/** Tokens. */
	string[],
	/** Clearing prices. */
	(number | bigint | string)[],
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
			undefined, // unused
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

/**
 * A class used for tracking tokens when encoding settlements.
 *
 * This is used as settlement trades reference tokens by index instead of
 * directly by address for multiple reasons:
 * - Reduce encoding size of orders to save on `calldata` gas.
 * - Direct access to a token's clearing price on settlement instead of
 *   requiring a search.
 */
export class TokenRegistry {
	private readonly _tokens: string[] = [];
	private readonly _tokenMap: Record<string, number | undefined> = {};

	constructor(private adapter?: EthereumClientAdapter) {}

	/**
	 * Gets the array of token addresses currently stored in the registry.
	 */
	public get addresses(): string[] {
		return this._tokens.slice();
	}

	/**
	 * Retrieves the token index for the specified token address. If the token is
	 * not in the registry, it will be added.
	 *
	 * @param token The token address to add to the registry.
	 * @return The token index.
	 */
	public index(token: string): number {
		// Normalize the address with the adapter if available
		const tokenAddress = this.adapter
			? this.adapter.getAddress(token).value
			: token;

		let tokenIndex = this._tokenMap[tokenAddress];
		if (tokenIndex === undefined) {
			tokenIndex = this._tokens.length;
			this._tokens.push(tokenAddress);
			this._tokenMap[tokenAddress] = tokenIndex;
		}

		return tokenIndex;
	}
}

/**
 * Settlement utility functions
 */

// biome-ignore lint/complexity/noStaticOnlyClass: <explanation>
export class SettlementUtils {
	/**
	 * Encodes signing scheme as a bitfield.
	 */
	static encodeSigningScheme(scheme: SigningScheme): number {
		return SettlementUtils.encodeFlag("signingScheme", scheme);
	}

	/**
	 * Decodes signing scheme from a bitfield.
	 */
	static decodeSigningScheme(flags: number | bigint | string): SigningScheme {
		return SettlementUtils.decodeFlag("signingScheme", flags);
	}

	/**
	 * Encodes order flags as a bitfield.
	 */
	static encodeOrderFlags(flags: OrderFlags): number {
		return (
			SettlementUtils.encodeFlag("kind", flags.kind) |
			SettlementUtils.encodeFlag("partiallyFillable", flags.partiallyFillable) |
			SettlementUtils.encodeFlag(
				"sellTokenBalance",
				flags.sellTokenBalance ?? OrderBalance.ERC20,
			) |
			SettlementUtils.encodeFlag(
				"buyTokenBalance",
				normalizeBuyTokenBalance(flags.buyTokenBalance),
			)
		);
	}

	/**
	 * Decode order flags from a bitfield.
	 */
	static decodeOrderFlags(flags: number | bigint | string): OrderFlags {
		return {
			kind: SettlementUtils.decodeFlag("kind", flags),
			partiallyFillable: SettlementUtils.decodeFlag("partiallyFillable", flags),
			sellTokenBalance: SettlementUtils.decodeFlag("sellTokenBalance", flags),
			buyTokenBalance: SettlementUtils.decodeFlag("buyTokenBalance", flags),
		};
	}

	/**
	 * Encodes trade flags as a bitfield.
	 */
	static encodeTradeFlags(flags: TradeFlags): number {
		return (
			SettlementUtils.encodeOrderFlags(flags) |
			SettlementUtils.encodeSigningScheme(flags.signingScheme)
		);
	}

	/**
	 * Decode trade flags from a bitfield.
	 */
	static decodeTradeFlags(flags: number | bigint | string): TradeFlags {
		return {
			...SettlementUtils.decodeOrderFlags(flags),
			signingScheme: SettlementUtils.decodeSigningScheme(flags),
		};
	}

	/**
	 * Helper to encode flag values
	 */
	private static encodeFlag<K extends FlagKey>(
		key: K,
		flag: FlagValue<K>,
	): number {
		const index = FLAG_MASKS[key].options.findIndex(
			(search: unknown) => search === flag,
		);
		if (index === -1) {
			throw new Error(`Bad key/value pair to encode: ${key}/${flag}`);
		}
		return index << FLAG_MASKS[key].offset;
	}

	/**
	 * Helper to count the smallest mask needed for options
	 */
	private static mask(options: readonly unknown[]): number {
		const num = options.length;
		const bitCount = 32 - Math.clz32(num - 1);
		return (1 << bitCount) - 1;
	}

	/**
	 * Helper to decode flag values
	 */
	private static decodeFlag<K extends FlagKey>(
		key: K,
		flag: number | bigint | string,
	): FlagValue<K> {
		const { offset, options } = FLAG_MASKS[key];
		// Convert to number safely
		const numberFlags =
			typeof flag === "bigint"
				? Number(flag)
				: typeof flag === "string"
					? Number.parseInt(flag)
					: flag;

		const index = (numberFlags >> offset) & SettlementUtils.mask(options);
		// This type casting should not be needed
		const decoded = options[index] as FlagValue<K>;
		if (decoded === undefined || index < 0) {
			throw new Error(
				`Invalid input flag for ${key}: 0b${numberFlags.toString(2)}`,
			);
		}
		return decoded;
	}
}

/**
 * A class for building calldata for a settlement.
 *
 * The encoder ensures that token addresses are kept track of and performs
 * necessary computation in order to map each token addresses to IDs to
 * properly encode order parameters for trades.
 */
export class SettlementEncoder {
	private readonly _tokens: TokenRegistry;
	private readonly _trades: Trade[] = [];
	private readonly _interactions: Record<InteractionStage, Interaction[]> = {
		[InteractionStage.PRE]: [],
		[InteractionStage.INTRA]: [],
		[InteractionStage.POST]: [],
	};
	private readonly _orderRefunds: OrderRefunds = {
		filledAmounts: [],
		preSignatures: [],
	};

	/**
	 * Creates a new settlement encoder instance.
	 * @param domain Domain used for signing orders.
	 * @param adapter Ethereum client adapter for blockchain operations.
	 */
	public constructor(
		public readonly domain: TypedDataDomain,
		private readonly adapter?: EthereumClientAdapter,
	) {
		this._tokens = new TokenRegistry(adapter);
	}

	/**
	 * Gets the array of token addresses used by the currently encoded orders.
	 */
	public get tokens(): string[] {
		return this._tokens.addresses;
	}

	/**
	 * Gets the encoded trades.
	 */
	public get trades(): Trade[] {
		return this._trades.slice();
	}

	/**
	 * Gets all encoded interactions for all stages.
	 *
	 * Note that order refund interactions are included as post-interactions.
	 */
	public get interactions(): [Interaction[], Interaction[], Interaction[]] {
		return [
			this._interactions[InteractionStage.PRE].slice(),
			this._interactions[InteractionStage.INTRA].slice(),
			[
				...this._interactions[InteractionStage.POST],
				...this.encodedOrderRefunds,
			],
		];
	}

	/**
	 * Gets the order refunds encoded as interactions.
	 */
	public get encodedOrderRefunds(): Interaction[] {
		const { filledAmounts, preSignatures } = this._orderRefunds;
		if (filledAmounts.length + preSignatures.length === 0) {
			return [];
		}

		const settlement = this.domain.verifyingContract;
		if (settlement === undefined) {
			throw new Error("domain missing settlement contract address");
		}

		if (!this.adapter) {
			throw new Error("Adapter is required for encoding order refunds");
		}

		const interactions = [];

		// Add filledAmounts interaction if needed
		if (filledAmounts.length > 0) {
			interactions.push(
				normalizeInteraction({
					target: settlement,
					callData: this.adapter.encodeFunction(
						[
							{
								name: "freeFilledAmountStorage",
								inputs: [{ type: "bytes[]" }],
							},
						],
						"freeFilledAmountStorage",
						[filledAmounts],
					),
				}),
			);
		}

		// Add preSignatures interaction if needed
		if (preSignatures.length > 0) {
			interactions.push(
				normalizeInteraction({
					target: settlement,
					callData: this.adapter.encodeFunction(
						[
							{
								name: "freePreSignatureStorage",
								inputs: [{ type: "bytes[]" }],
							},
						],
						"freePreSignatureStorage",
						[preSignatures],
					),
				}),
			);
		}

		return interactions;
	}

	/**
	 * Returns a clearing price vector for the current settlement tokens from the
	 * provided price map.
	 */
	public clearingPrices(prices: Prices): (number | bigint | string)[] {
		return this.tokens.map((token) => {
			const price = prices[token];
			if (price === undefined) {
				throw new Error(`missing price for token ${token}`);
			}
			return price;
		});
	}

	/**
	 * Encodes a trade from a signed order and executed amount.
	 */
	public encodeTrade(
		order: Order,
		signature: Signature,
		{ executedAmount }: Partial<TradeExecution> = {},
	): void {
		if (order.partiallyFillable && executedAmount === undefined) {
			throw new Error("missing executed amount for partially fillable trade");
		}

		const tradeFlags = {
			...order,
			signingScheme: signature.scheme,
		};
		const o = normalizeOrder(order);

		// Encode the signature
		let signatureData: string;
		switch (signature.scheme) {
			case SigningScheme.EIP712:
			case SigningScheme.ETHSIGN:
				if (!this.adapter)
					throw new Error("Adapter required for signature encoding");
				signatureData = this.adapter.joinSignature(signature.data);
				break;
			case SigningScheme.EIP1271:
				// This would need adapter implementation
				if (!this.adapter)
					throw new Error("Adapter required for EIP1271 signatures");
				signatureData = this.adapter.encodeEip1271SignatureData(signature.data);
				break;
			case SigningScheme.PRESIGN:
				if (!this.adapter)
					throw new Error("Adapter required for PRESIGN signatures");
				signatureData = this.adapter.getAddress(signature.data).value;
				break;
			default:
				throw new Error("unsupported signing scheme");
		}

		this._trades.push({
			sellTokenIndex: this._tokens.index(o.sellToken),
			buyTokenIndex: this._tokens.index(o.buyToken),
			receiver: o.receiver,
			sellAmount: o.sellAmount,
			buyAmount: o.buyAmount,
			validTo: o.validTo,
			appData: o.appData,
			feeAmount: o.feeAmount,
			flags: SettlementUtils.encodeTradeFlags(tradeFlags),
			executedAmount: executedAmount ?? 0,
			signature: signatureData,
		});
	}

	/**
	 * Signs an order and encodes a trade with that order.
	 */
	public async signEncodeTrade(
		order: Order,
		signer: SignerContext,
		scheme: EcdsaSigningScheme,
		tradeExecution?: Partial<TradeExecution>,
	): Promise<void> {
		if (!this.adapter) {
			throw new Error("Adapter is required for signing operations");
		}

		const signature = await this.adapter.signOrder(this.domain, order, signer);

		this.encodeTrade(order, signature, tradeExecution);
	}

	/**
	 * Encodes the input interaction in the packed format accepted by the smart
	 * contract and adds it to the interactions encoded so far.
	 */
	public encodeInteraction(
		interaction: InteractionLike,
		stage: InteractionStage = InteractionStage.INTRA,
	): void {
		this._interactions[stage].push(normalizeInteraction(interaction));
	}

	/**
	 * Encodes order UIDs for gas refunds.
	 */
	public encodeOrderRefunds(orderRefunds: Partial<OrderRefunds>): void {
		if (this.domain.verifyingContract === undefined) {
			throw new Error("domain missing settlement contract address");
		}

		const filledAmounts = orderRefunds.filledAmounts ?? [];
		const preSignatures = orderRefunds.preSignatures ?? [];

		// Verify all order UIDs are valid
		if (!this.adapter) {
			throw new Error("Adapter required for validating order UIDs");
		}

		for (const orderUid of [...filledAmounts, ...preSignatures]) {
			const bytes = this.adapter.arrayify(orderUid);
			if (bytes.length !== ORDER_UID_LENGTH) {
				throw new Error("one or more invalid order UIDs");
			}
		}

		this._orderRefunds.filledAmounts.push(...filledAmounts);
		this._orderRefunds.preSignatures.push(...preSignatures);
	}

	/**
	 * Returns the encoded settlement parameters.
	 */
	public encodedSettlement(prices: Prices): EncodedSettlement {
		return [
			this.tokens,
			this.clearingPrices(prices),
			this.trades,
			this.interactions,
		];
	}

	/**
	 * Returns an encoded settlement that exclusively performs setup interactions.
	 */
	public static encodedSetup(
		adapter: EthereumClientAdapter,
		...interactions: InteractionLike[]
	): EncodedSettlement {
		const encoder = new SettlementEncoder({ name: "unused" }, adapter);
		for (const interaction of interactions) {
			encoder.encodeInteraction(interaction);
		}
		return encoder.encodedSettlement({});
	}
}

/**
 * Decodes an order from a settlement trade.
 */
export function decodeOrder(trade: Trade, tokens: string[]): Order {
	// Convert indices to numbers
	const sellTokenIndex =
		typeof trade.sellTokenIndex === "bigint"
			? Number(trade.sellTokenIndex)
			: typeof trade.sellTokenIndex === "string"
				? Number.parseInt(trade.sellTokenIndex)
				: trade.sellTokenIndex;

	const buyTokenIndex =
		typeof trade.buyTokenIndex === "bigint"
			? Number(trade.buyTokenIndex)
			: typeof trade.buyTokenIndex === "string"
				? Number.parseInt(trade.buyTokenIndex)
				: trade.buyTokenIndex;

	if (Math.max(sellTokenIndex, buyTokenIndex) >= tokens.length) {
		throw new Error("Invalid trade");
	}

	return {
		sellToken: tokens[sellTokenIndex],
		buyToken: tokens[buyTokenIndex],
		receiver: trade.receiver,
		sellAmount: trade.sellAmount,
		buyAmount: trade.buyAmount,
		validTo:
			typeof trade.validTo === "bigint"
				? Number(trade.validTo)
				: typeof trade.validTo === "string"
					? Number.parseInt(trade.validTo)
					: trade.validTo,
		appData: trade.appData as `0x${string}`,
		feeAmount: trade.feeAmount,
		...SettlementUtils.decodeOrderFlags(trade.flags),
	};
}
