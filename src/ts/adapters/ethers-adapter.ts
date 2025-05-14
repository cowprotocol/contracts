// src/ts/adapters/ethers-adapter.ts
import { ethers } from "ethers";
import { ORDER_TYPE_FIELDS } from "../constants";
import type { NormalizedOrder } from "../order";
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

export class EthersAdapter implements EthereumClientAdapter {
	getAddress(address: string): Address {
		return { value: ethers.utils.getAddress(address) };
	}

	keccak256(data: Uint8Array): string {
		return ethers.utils.keccak256(data);
	}

	hashTypedData(
		domain: TypedDataDomain,
		types: TypedDataTypes,
		data: TypedDataValue,
	): string {
		// Convert domain to ethers format
		const ethersDomain: SignerDomain = {
			name: domain.name,
			version: domain.version,
			chainId: domain.chainId,
			verifyingContract: domain.verifyingContract,
		};

		return ethers.utils._TypedDataEncoder.hash(ethersDomain, types, data);
	}

	formatAmount(amount: bigint): string {
		return amount.toString();
	}

	parseAmount(amount: string): bigint {
		return BigInt(amount);
	}

	arrayify(hex: string): Uint8Array {
		return ethers.utils.arrayify(hex);
	}

	hexlify(bytes: Uint8Array): string {
		return ethers.utils.hexlify(bytes);
	}

	joinSignature(
		signature: string | { r: string; s: string; v: number },
	): string {
		return ethers.utils.joinSignature(signature);
	}

	encodeEip1271SignatureData(data: {
		verifier: string;
		signature: string | Uint8Array;
	}): string {
		return ethers.utils.solidityPack(
			["address", "bytes"],
			[data.verifier, data.signature],
		);
	}

	encodeFunction(
		abi: Array<{ name: string; inputs?: Array<{ type: string }> }>,
		functionName: string,
		args: unknown[],
	): string {
		const iface = new ethers.utils.Interface(
			abi.map((fn) => {
				const inputs = fn.inputs
					? `(${fn.inputs.map((i) => i.type).join(",")})`
					: "()";
				return `function ${fn.name}${inputs}`;
			}),
		);
		return iface.encodeFunctionData(functionName, args);
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

	private normalizeOrder(order: Order): NormalizedOrder {
		return {
			...order,
			receiver: order.receiver || ethers.constants.AddressZero,
			sellTokenBalance: order.sellTokenBalance || "erc20",
			buyTokenBalance: order.buyTokenBalance || "erc20",
			sellAmount: order.sellAmount,
			buyAmount: order.buyAmount,
			feeAmount: order.feeAmount,
		};
	}
}
