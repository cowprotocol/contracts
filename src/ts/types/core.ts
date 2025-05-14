import type { SigningScheme } from "./signing";

interface ArrayLike<T> {
	readonly length: number;
	readonly [n: number]: T;
}

/**
 * A signature-like type.
 */
export type SignatureLike =
	| ArrayLike<number>
	| {
			r: string;
			s?: string;
			_vs?: string;
			recoveryParam?: number;
			v?: number;
	  };

/**
 * EIP-712 typed data domain.
 */
export interface TypedDataDomain {
	name?: string;
	version?: string;
	chainId?: bigint;
	verifyingContract?: `0x${string}`;
	salt?: `0x${string}`;
}

export interface TypedDataField {
	name: string;
	type: string;
}
/**
 * EIP-712 typed data type definitions.
 */
export type TypedDataTypes = {
	[key: string]: TypedDataField[];
};

/**
 * Checks whether the specified provider is a JSON RPC provider.
 */
export function isJsonRpcProvider(provider: never) {
	return "send" in provider;
}

export interface Address {
	readonly value: string;
}

export interface SignatureData {
	verifier: string;
	signature: Uint8Array;
}
