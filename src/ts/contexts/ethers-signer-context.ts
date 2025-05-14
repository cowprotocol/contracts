import type { Signer, ethers } from "ethers";

import type {
	SignerContext,
	SignerDomain,
	TypedDataTypes,
	TypedDataValue,
} from "../types/signing";

/**
 * Ethers EIP-712 typed data signer interface.
 */
export interface TypedDataSigner extends Signer {
	/**
	 * Signs the typed data value with types data structure for domain using the
	 * EIP-712 specification.
	 */
	_signTypedData: typeof ethers.VoidSigner.prototype._signTypedData;
}

/**
 * Checks whether the specified signer is a typed data signer.
 */
export function isTypedDataSigner(signer: Signer): signer is TypedDataSigner {
	return "_signTypedData" in signer;
}

export class EthersSignerContext implements SignerContext {
	constructor(private signer: ethers.Signer) {}

	async signTypedData(
		domain: SignerDomain,
		types: TypedDataTypes,
		data: TypedDataValue,
	): Promise<string> {
		if (isTypedDataSigner(this.signer)) {
			return await this.signer._signTypedData(domain, types, data);
		}
		throw new Error("Ethers signer does not support typed data signing");
	}

	async signMessage(message: Uint8Array): Promise<string> {
		return await this.signer.signMessage(message);
	}

	async getAddress(): Promise<string> {
		return await this.signer.getAddress();
	}
}
