import { type BigNumberish, type BytesLike, ethers } from "ethers";

import { ORDER_TYPE_FIELDS } from "./constants";
import type { TypedDataDomain, TypedDataTypes } from "./types/core";
import { type Order, OrderBalance, type Timestamp } from "./types/order";

/**
 * Gnosis Protocol v2 order cancellation data.
 */
export interface OrderCancellations {
	/**
	 * The unique identifier of the order to be cancelled.
	 */
	orderUids: BytesLike[];
}

/**
 * Marker address to indicate that an order is buying Ether.
 *
 * Note that this address is only has special meaning in the `buyToken` and will
 * be treated as a ERC20 token address in the `sellToken` position, causing the
 * settlement to revert.
 */
export const BUY_ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

/**
 * Gnosis Protocol v2 order flags.
 */
export type OrderFlags = Pick<
	Order,
	"kind" | "partiallyFillable" | "sellTokenBalance" | "buyTokenBalance"
>;

/**
 * A hash-like app data value.
 */
export type HashLike = BytesLike | number;

/**
 * Normalizes a timestamp value to a Unix timestamp.
 * @param time The timestamp value to normalize.
 * @return Unix timestamp or number of seconds since the Unix Epoch.
 */
export function timestamp(t: Timestamp): number {
	return typeof t === "number" ? t : ~~(t.getTime() / 1000);
}

/**
 * Normalizes an app data value to a 32-byte hash.
 * @param hashLike A hash-like value to normalize.
 * @returns A 32-byte hash encoded as a hex-string.
 */
export function hashify(h: HashLike): string {
	return typeof h === "number"
		? `0x${h.toString(16).padStart(64, "0")}`
		: ethers.utils.hexZeroPad(h, 32);
}

/**
 * Normalizes the balance configuration for a buy token. Specifically, this
 * function ensures that {@link OrderBalance.EXTERNAL} gets normalized to
 * {@link OrderBalance.ERC20}.
 *
 * @param balance The balance configuration.
 * @returns The normalized balance configuration.
 */
export function normalizeBuyTokenBalance(
	balance: OrderBalance | undefined,
): OrderBalance.ERC20 | OrderBalance.INTERNAL {
	switch (balance) {
		case undefined:
		case OrderBalance.ERC20:
		case OrderBalance.EXTERNAL:
			return OrderBalance.ERC20;
		case OrderBalance.INTERNAL:
			return OrderBalance.INTERNAL;
		default:
			throw new Error(`invalid order balance ${balance}`);
	}
}

/**
 * Normalized representation of an {@link Order} for EIP-712 operations.
 */
export type NormalizedOrder = Omit<
	Order,
	"validTo" | "appData" | "kind" | "sellTokenBalance" | "buyTokenBalance"
> & {
	receiver: string;
	validTo: number;
	appData: string;
	kind: "sell" | "buy";
	sellTokenBalance: "erc20" | "external" | "internal";
	buyTokenBalance: "erc20" | "internal";
	sellAmount: string;
	buyAmount: string;
	feeAmount: string;
};

/**
 * Normalizes an order for hashing and signing, so that it can be used with
 * Ethers.js for EIP-712 operations.
 * @param hashLike A hash-like value to normalize.
 * @returns A 32-byte hash encoded as a hex-string.
 */
export function normalizeOrder(order: Order): NormalizedOrder {
	if (order.receiver === ethers.constants.AddressZero) {
		throw new Error("receiver cannot be address(0)");
	}

	const normalizedOrder = {
		...order,
		sellTokenBalance: order.sellTokenBalance ?? OrderBalance.ERC20,
		receiver: order.receiver ?? ethers.constants.AddressZero,
		validTo: timestamp(order.validTo),
		appData: hashify(order.appData),
		buyTokenBalance: normalizeBuyTokenBalance(order.buyTokenBalance),
	};
	return normalizedOrder;
}

/**
 * Compute the 32-byte signing hash for the specified order.
 *
 * @param domain The EIP-712 domain separator to compute the hash for.
 * @param types The order to compute the digest for.
 * @return Hex-encoded 32-byte order digest.
 */
export function hashTypedData(
	domain: TypedDataDomain,
	types: TypedDataTypes,
	data: Record<string, unknown>,
): string {
	return ethers.utils._TypedDataEncoder.hash(domain, types, data);
}

/**
 * Compute the 32-byte signing hash for the specified order.
 *
 * @param domain The EIP-712 domain separator to compute the hash for.
 * @param order The order to compute the digest for.
 * @return Hex-encoded 32-byte order digest.
 */
export function hashOrder(domain: TypedDataDomain, order: Order): string {
	return hashTypedData(
		domain,
		{ Order: ORDER_TYPE_FIELDS },
		normalizeOrder(order),
	);
}

/**
 * The byte length of an order UID.
 */
export const ORDER_UID_LENGTH = 56;

/**
 * Order unique identifier parameters.
 */
export interface OrderUidParams {
	/**
	 * The EIP-712 order struct hash.
	 */
	orderDigest: string;
	/**
	 * The owner of the order.
	 */
	owner: string;
	/**
	 * The timestamp this order is valid until.
	 */
	validTo: number | Date;
}

/**
 * Computes the order UID for an order and the given owner.
 */
export function computeOrderUid(
	domain: TypedDataDomain,
	order: Order,
	owner: string,
): string {
	return packOrderUidParams({
		orderDigest: hashOrder(domain, order),
		owner,
		validTo: order.validTo,
	});
}

/**
 * Compute the unique identifier describing a user order in the settlement
 * contract.
 *
 * @param OrderUidParams The parameters used for computing the order's unique
 * identifier.
 * @returns A string that unequivocally identifies the order of the user.
 */
export function packOrderUidParams({
	orderDigest,
	owner,
	validTo,
}: OrderUidParams): string {
	return ethers.utils.solidityPack(
		["bytes32", "address", "uint32"],
		[orderDigest, owner, timestamp(validTo)],
	);
}

/**
 * Extracts the order unique identifier parameters from the specified bytes.
 *
 * @param orderUid The order UID encoded as a hexadecimal string.
 * @returns The extracted order UID parameters.
 */
export function extractOrderUidParams(orderUid: string): OrderUidParams {
	const bytes = ethers.utils.arrayify(orderUid);
	if (bytes.length !== ORDER_UID_LENGTH) {
		throw new Error("invalid order UID length");
	}

	const view = new DataView(bytes.buffer);
	return {
		orderDigest: ethers.utils.hexlify(bytes.subarray(0, 32)),
		owner: ethers.utils.getAddress(
			ethers.utils.hexlify(bytes.subarray(32, 52)),
		),
		validTo: view.getUint32(52),
	};
}
