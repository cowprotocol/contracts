// src/ts/adapters/viem-adapter.ts
import {
	encodeFunctionData,
	fromHex,
	parseAbiItem,
	toHex,
	getAddress as viemGetAddress,
	hashTypedData as viemHashTypedData,
	keccak256 as viemKeccak256,
} from "viem";
import { ORDER_TYPE_FIELDS } from "../constants";
import type { Address, TypedDataDomain } from "../types/core";
import type { Order, OrderSignature } from "../types/order";
import {
	type SignerContext,
	type SignerDomain,
	SigningScheme,
	type TypedDataTypes,
	type TypedDataValue,
} from "../types/signing";
import type { EthereumClientAdapter } from "./ethereum-client-adapter";

export class ViemAdapter implements EthereumClientAdapter {
	getAddress(address: string): Address {
		return { value: viemGetAddress(address as `0x${string}`) };
	}

	keccak256(data: Uint8Array): string {
		return viemKeccak256(data);
	}

	hashTypedData(
		domain: TypedDataDomain,
		types: TypedDataTypes,
		data: TypedDataValue,
	): string {
		const primaryType = Object.keys(types)[0];

		return viemHashTypedData({
			domain,
			primaryType,
			types,
			message: data,
		});
	}

	formatAmount(amount: bigint): string {
		return amount.toString();
	}

	parseAmount(amount: string): bigint {
		return BigInt(amount);
	}

	arrayify(hex: string): Uint8Array {
		return fromHex(hex as `0x${string}`, "bytes");
	}

	hexlify(bytes: Uint8Array): string {
		return toHex(bytes);
	}

	joinSignature(
		signature: string | { r: string; s: string; v: number },
	): string {
		// For viem, if it's already a string, return it as is
		if (typeof signature === "string") {
			return signature;
		}

		// Otherwise construct the signature string from r, s, v
		const { r, s, v } = signature;
		// Ensure v is properly formatted as a single byte
		const vByte = v < 27 ? v + 27 : v;
		return `${r}${s.slice(2)}${vByte.toString(16).padStart(2, "0")}`;
	}

	encodeEip1271SignatureData(data: {
		verifier: string;
		signature: string | Uint8Array;
	}): string {
		// Convert signature to hex string if it's a Uint8Array
		const sigHex =
			typeof data.signature === "string"
				? data.signature
				: toHex(data.signature);

		// Concatenate the address and signature
		return `${this.getAddress(data.verifier).value}${sigHex.startsWith("0x") ? sigHex.slice(2) : sigHex}`;
	}

	encodeFunction(
		abi: Array<{ name: string; inputs?: Array<{ type: string }> }>,
		functionName: string,
		args: unknown[],
	): string {
		// Find the function in the ABI
		const funcAbi = abi.find((fn) => fn.name === functionName);
		if (!funcAbi) {
			throw new Error(`Function ${functionName} not found in ABI`);
		}

		// Create the function signature
		const inputs = funcAbi.inputs || [];
		const signature = `${functionName}(${inputs.map((i) => i.type).join(",")})`;

		// Encode the function data
		return encodeFunctionData({
			abi: [parseAbiItem(`function ${signature}`)],
			functionName,
			args,
		});
	}

	hashOrder(domain: TypedDataDomain, order: Order): string {
		const normalizedOrder = this.normalizeOrder(order);
		return this.hashTypedData(
			domain,
			{ Order: ORDER_TYPE_FIELDS },
			normalizedOrder,
		);
	}

	async signOrder(
		domain: TypedDataDomain,
		order: Order,
		signer: SignerContext,
	): Promise<OrderSignature> {
		const normalizedOrder = this.normalizeOrder(order);

		// Convert domain to signer format
		const signerDomain: SignerDomain = {
			name: domain.name,
			version: domain.version,
			chainId: domain.chainId,
			verifyingContract: domain.verifyingContract,
		};

		const signature = await signer.signTypedData(
			signerDomain,
			{ Order: ORDER_TYPE_FIELDS },
			normalizedOrder,
		);

		return {
			scheme: SigningScheme.EIP712,
			data: signature,
		};
	}

	private normalizeOrder(order: Order) {
		return {
			...order,
			receiver: order.receiver || "0x0000000000000000000000000000000000000000",
			sellTokenBalance: order.sellTokenBalance || "erc20",
			buyTokenBalance: order.buyTokenBalance || "erc20",
			sellAmount: order.sellAmount.toString(),
			buyAmount: order.buyAmount.toString(),
			feeAmount: order.feeAmount.toString(),
		};
	}
}
