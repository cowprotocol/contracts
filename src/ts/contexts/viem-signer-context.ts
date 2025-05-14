import type { Account, WalletClient } from "viem";
import type { SignerContext, SignerDomain } from "../types/signing";

export class ViemSignerContext implements SignerContext {
	constructor(
		private account: Account,
		private client: WalletClient,
	) {}

	async signTypedData(
		domain: SignerDomain,
		types: Record<string, Array<{ name: string; type: string }>>,
		data: Record<string, any>,
		primaryType?: string,
	): Promise<string> {
		const actualPrimaryType = primaryType || Object.keys(types)[0];

		return await this.client.signTypedData({
			account: this.account,
			domain,
			types,
			primaryType: actualPrimaryType,
			message: data,
		});
	}

	async signMessage(message: Uint8Array): Promise<string> {
		return await this.client.signMessage({
			account: this.account,
			message: { raw: message },
		});
	}

	getAddress(): string {
		if (typeof this.account === "string") {
			return this.account;
		}
		return this.account.address;
	}
}
