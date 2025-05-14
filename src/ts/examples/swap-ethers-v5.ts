import { ethers } from "ethers";
import { EthersAdapter } from "../adapters/ethers-adapter";
import { EthersSignerContext } from "../contexts/ethers-signer-context";
import { SwapEncoder } from "../swap";
import type { TypedDataDomain } from "../types/core";
import { OrderBalance, OrderKind } from "../types/order";
import { SigningScheme } from "../types/signing";

const VALID_TO = 1747261637;
async function ethersExample() {
	const wallet = new ethers.Wallet(
		// SOME RANDOM GENERATED PRIVATE KEY
		"0x4de4739ebdab31d6a36e5ecef027c6ab2fd1a80cf2692c3861ba1ccfeb6cf8b8",
	);

	const provider = new ethers.providers.JsonRpcProvider(
		"https://gnosis.drpc.org",
	);
	const connectedWallet = wallet.connect(provider);

	const adapter = new EthersAdapter();

	const signer = new EthersSignerContext(connectedWallet);

	const domain = {
		name: "Gnosis Protocol",
		version: "v2",
		chainId: 1n,
		verifyingContract: "0x9008D19f58AAbD9eD0D60971565AA8510560ab41",
	} as const;

	const order = {
		sellToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
		buyToken: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
		sellAmount: ethers.utils.parseEther("1").toBigInt(),
		buyAmount: ethers.utils.parseEther("1800").toBigInt(),
		validTo: VALID_TO,
		appData:
			"0x0000000000000000000000000000000000000000000000000000000000000000",
		feeAmount: ethers.utils.parseEther("0.001").toBigInt(),
		kind: OrderKind.SELL,
		partiallyFillable: false,
		sellTokenBalance: OrderBalance.ERC20,
		buyTokenBalance: OrderBalance.ERC20,
	} as const;

	const swaps = [
		{
			poolId:
				"0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
			assetIn: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
			assetOut: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
			amount: order.sellAmount,
			userData: "0x",
		},
	];

	const encodedSwap = await SwapEncoder.encodeSwap(
		adapter,
		domain,
		swaps,
		order,
		signer,
		SigningScheme.EIP712,
	);
	console.log("private_key", wallet.privateKey);
	console.log("Encoded Swap:", encodedSwap);
}

ethersExample();
