import type { EthereumClientAdapter } from "./adapters/ethereum-client-adapter";
import { SettlementEncoder, TokenRegistry } from "./settlement";
import type { EcdsaSigningScheme, Signature } from "./sign";
import type { TypedDataDomain } from "./types/core";
import { type Order, OrderKind } from "./types/order";
import type { Trade } from "./types/settlement";
import type { SignerContext } from "./types/signing";

/**
 * A Balancer swap used for settling a single order against Balancer pools.
 */
export interface Swap {
	/**
	 * The ID of the pool for the swap.
	 */
	poolId: string;
	/**
	 * The swap input token address.
	 */
	assetIn: string;
	/**
	 * The swap output token address.
	 */
	assetOut: string;
	/**
	 * The amount to swap. This will ether be a fixed input amount when swapping
	 * a sell order, or a fixed output amount when swapping a buy order.
	 */
	amount: bigint | string;
	/**
	 * Optional additional pool user data required for the swap.
	 *
	 * This additional user data is pool implementation specific, and allows pools
	 * to extend the Vault pool interface.
	 */
	userData?: string;
}

/**
 * An encoded Balancer swap request that can be used as input to the settlement
 * contract.
 */
export interface BatchSwapStep {
	/**
	 * The ID of the pool for the swap.
	 */
	poolId: string;
	/**
	 * The index of the input token.
	 *
	 * Settlement swap calls encode tokens as an array, this number represents an
	 * index into that array.
	 */
	assetInIndex: number;
	/**
	 * The index of the output token.
	 */
	assetOutIndex: number;
	/**
	 * The amount to swap.
	 */
	amount: bigint | string;
	/**
	 * Additional pool user data required for the swap.
	 */
	userData: string;
}

/**
 * Swap execution parameters.
 */
export interface SwapExecution {
	/**
	 * The limit amount for the swap.
	 *
	 * This allows settlement submission to define a tighter slippage than what
	 * was specified by the order in order to reduce MEV opportunity.
	 */
	limitAmount: bigint | string;
}

/**
 * Encoded swap parameters.
 */
export type EncodedSwap = [
	/** Swap requests. */
	BatchSwapStep[],
	/** Tokens. */
	string[],
	/** Encoded trade. */
	Trade,
];

/**
 * Encodes a swap as a {@link BatchSwapStep} to be used with the settlement
 * contract.
 */
export function encodeSwapStep(
	tokens: TokenRegistry,
	swap: Swap,
): BatchSwapStep {
	return {
		poolId: swap.poolId,
		assetInIndex: tokens.index(swap.assetIn),
		assetOutIndex: tokens.index(swap.assetOut),
		amount: swap.amount,
		userData: swap.userData || "0x",
	};
}

/**
 * A class for building calldata for a swap.
 *
 * The encoder ensures that token addresses are kept track of and performs
 * necessary computation in order to map each token addresses to IDs to
 * properly encode swap requests and the trade.
 */
export class SwapEncoder {
	private readonly _tokens = new TokenRegistry();
	private readonly _swaps: BatchSwapStep[] = [];
	private _trade: Trade | undefined = undefined;

	/**
	 * Creates a new settlement encoder instance.
	 *
	 * @param domain Domain used for signing orders.
	 * @param adapter The blockchain adapter to use
	 */
	public constructor(
		public readonly domain: TypedDataDomain,
		private readonly adapter: EthereumClientAdapter,
	) {}

	/**
	 * Gets the array of token addresses used by the currently encoded swaps.
	 */
	public get tokens(): string[] {
		return this._tokens.addresses;
	}

	/**
	 * Gets the encoded swaps.
	 */
	public get swaps(): BatchSwapStep[] {
		return this._swaps.slice();
	}

	/**
	 * Gets the encoded trade.
	 */
	public get trade(): Trade {
		if (this._trade === undefined) {
			throw new Error("trade not encoded");
		}
		return this._trade;
	}

	/**
	 * Encodes the swap as a swap request and appends it to the swaps encoded so
	 * far.
	 *
	 * @param swap The Balancer swap to encode.
	 */
	public encodeSwapStep(...swaps: Swap[]): void {
		this._swaps.push(
			...swaps.map((swap) => encodeSwapStep(this._tokens, swap)),
		);
	}

	/**
	 * Encodes a trade from a signed order.
	 *
	 * Additionally, if the order references new tokens that the encoder has not
	 * yet seen, they are added to the tokens array.
	 *
	 * @param order The order of the trade to encode.
	 * @param signature The signature for the order data.
	 */
	public encodeTrade(
		order: Order,
		signature: Signature,
		swapExecution?: Partial<SwapExecution>,
	): void {
		const { limitAmount } = {
			limitAmount:
				order.kind === OrderKind.SELL ? order.buyAmount : order.sellAmount,
			...swapExecution,
		};

		// Create a settlement encoder with our domain and adapter
		const settlementEncoder = new SettlementEncoder(this.domain, this.adapter);

		// Encode the trade
		settlementEncoder.encodeTrade(order, signature, {
			executedAmount: limitAmount,
		});

		// Get the encoded trade (this will be the first trade in the encoder)
		this._trade = settlementEncoder.trades[0];
	}

	/**
	 * Signs an order and encodes a trade with that order.
	 *
	 * @param order The order to sign for the trade.
	 * @param signer The signer to use for signing the order.
	 * @param scheme The signing scheme to use.
	 * @param swapExecution Optional swap execution parameters.
	 */
	public async signEncodeTrade(
		order: Order,
		signer: SignerContext,
		scheme: EcdsaSigningScheme,
		swapExecution?: Partial<SwapExecution>,
	): Promise<void> {
		if (!this.adapter) {
			throw new Error("Adapter must be provided for signing operations");
		}

		const signature = await this.adapter.signOrder(this.domain, order, signer);
		this.encodeTrade(order, signature, swapExecution);
	}

	/**
	 * Returns the encoded swap parameters for the current state of the encoder.
	 *
	 * This method with raise an exception if a trade has not been encoded.
	 */
	public encodedSwap(): EncodedSwap {
		return [this.swaps, this.tokens, this.trade];
	}

	// Static method overloads that match your original structure
	public static encodeSwap(
		swaps: Swap[],
		order: Order,
		signature: Signature,
	): EncodedSwap;
	public static encodeSwap(
		swaps: Swap[],
		order: Order,
		signature: Signature,
		swapExecution: Partial<SwapExecution> | undefined,
	): EncodedSwap;
	public static encodeSwap(
		adapter: EthereumClientAdapter,
		domain: TypedDataDomain,
		swaps: Swap[],
		order: Order,
		signer: SignerContext,
		scheme: EcdsaSigningScheme,
	): Promise<EncodedSwap>;
	public static encodeSwap(
		adapter: EthereumClientAdapter,
		domain: TypedDataDomain,
		swaps: Swap[],
		order: Order,
		signer: SignerContext,
		scheme: EcdsaSigningScheme,
		swapExecution: Partial<SwapExecution> | undefined,
	): Promise<EncodedSwap>;

	/**
	 * Utility method for encoding a direct swap between an order and Balancer
	 * pools.
	 *
	 * This method functions identically to using a {@link SwapEncoder} and is
	 * provided as a short-cut.
	 */
	public static encodeSwap(
		...args:
			| [Swap[], Order, Signature]
			| [Swap[], Order, Signature, Partial<SwapExecution> | undefined]
			| [
					EthereumClientAdapter,
					TypedDataDomain,
					Swap[],
					Order,
					SignerContext,
					EcdsaSigningScheme,
			  ]
			| [
					EthereumClientAdapter,
					TypedDataDomain,
					Swap[],
					Order,
					SignerContext,
					EcdsaSigningScheme,
					Partial<SwapExecution> | undefined,
			  ]
	): EncodedSwap | Promise<EncodedSwap> {
		// Case 1: [swaps, order, signature, ?swapExecution]
		if (!args[0] || typeof args[0] !== "object" || "poolId" in args[0]) {
			const [swaps, order, signature, swapExecution] = args as [
				Swap[],
				Order,
				Signature,
				Partial<SwapExecution> | undefined,
			];

			const encoder = new SwapEncoder({} as TypedDataDomain);
			encoder.encodeSwapStep(...swaps);
			encoder.encodeTrade(order, signature, swapExecution);
			return encoder.encodedSwap();
		}

		// Case 2: [adapter, domain, swaps, order, signer, scheme, ?swapExecution]
		const [adapter, domain, swaps, order, signer, scheme, swapExecution] =
			args as [
				EthereumClientAdapter,
				TypedDataDomain,
				Swap[],
				Order,
				SignerContext,
				EcdsaSigningScheme,
				Partial<SwapExecution> | undefined,
			];

		const encoder = new SwapEncoder(domain, adapter);
		encoder.encodeSwapStep(...swaps);
		return encoder
			.signEncodeTrade(order, signer, scheme, swapExecution)
			.then(() => encoder.encodedSwap());
	}
}
