import { http, createWalletClient, parseEther } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { mainnet } from "viem/chains";
import { ViemAdapter } from "../adapters/viem-adapter";
import { ViemSignerContext } from "../contexts/viem-signer-context";
import { SwapEncoder } from "../swap";
import type { TypedDataDomain } from "../types/core";
import { OrderBalance, OrderKind } from "../types/order";
import { SigningScheme } from "../types/signing";

const VALID_TO = 1747261637;

async function viemExample() {
	const account = privateKeyToAccount(
		// SOME RANDOM GENERATED PRIVATE KEY
		"0x4de4739ebdab31d6a36e5ecef027c6ab2fd1a80cf2692c3861ba1ccfeb6cf8b8",
	);

	const walletClient = createWalletClient({
		account,
		chain: mainnet,
		transport: http("https://gnosis.drpc.org"),
	});

	const adapter = new ViemAdapter();

	const signer = new ViemSignerContext(account, walletClient);

	const domain = {
		name: "Gnosis Protocol",
		version: "v2",
		chainId: 1n,
		verifyingContract: "0x9008D19f58AAbD9eD0D60971565AA8510560ab41",
	} as TypedDataDomain;

	const order = {
		sellToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
		buyToken: "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
		sellAmount: parseEther("1"), // 1 WETH
		buyAmount: parseEther("1800"), // 1800 DAI
		validTo: VALID_TO, // Valid for 1 hour
		appData:
			"0x0000000000000000000000000000000000000000000000000000000000000000",
		feeAmount: parseEther("0.001"), // 0.001 WETH fee
		kind: OrderKind.SELL,
		partiallyFillable: false,
		sellTokenBalance: OrderBalance.ERC20,
		buyTokenBalance: OrderBalance.ERC20,
	} as const;

	const swaps = [
		{
			poolId:
				"0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
			assetIn: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
			assetOut: "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
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

	console.log("Encoded Swap:", encodedSwap);
}

viemExample();
