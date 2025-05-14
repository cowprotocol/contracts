import type { Address, TypedDataDomain } from "../types/core";
import type { Order, OrderSignature } from "../types/order";
import type {
	SignerContext,
	TypedDataTypes,
	TypedDataValue,
} from "../types/signing";

export interface EthereumClientAdapter {
	// Address operations
	getAddress(address: string): Address;

	// Hashing operations
	keccak256(data: Uint8Array): string;
	hashTypedData(
		domain: TypedDataDomain,
		types: TypedDataTypes,
		data: TypedDataValue,
	): string;

	// Amount formatting
	formatAmount(amount: bigint): string;
	parseAmount(amount: string): bigint;

	// Order operations
	hashOrder(domain: TypedDataDomain, order: Order): string;
	signOrder(
		domain: TypedDataDomain,
		order: Order,
		signer: SignerContext,
	): Promise<OrderSignature>;

	// Data conversion
	arrayify(hex: string): Uint8Array;
	hexlify(bytes: Uint8Array): string;

	// Signature handling
	joinSignature(
		signature: string | { r: string; s: string; v: number },
	): string;
	encodeEip1271SignatureData(data: {
		verifier: string;
		signature: string | Uint8Array;
	}): string;

	// Function encoding
	encodeFunction(
		abi: Array<{ name: string; inputs?: Array<{ type: string }> }>,
		functionName: string,
		args: unknown[],
	): string;
}
