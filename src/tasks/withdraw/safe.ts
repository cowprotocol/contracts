import SafeApiKit from "@safe-global/api-kit";
import Safe, { EthersAdapter } from "@safe-global/protocol-kit";
import { SafeTransactionDataPartial } from "@safe-global/safe-core-sdk-types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

interface Transaction {
  authoringSafe: string;
  to: string;
  data: string;
}

function serviceUrlForNetwork(network: string): string {
  if (["goerli", "mainnet", "gnosis-chain", "sepolia"].includes(network)) {
    return `https://safe-transaction-${network}.safe.global`;
  } else if (network === "xdai") {
    return "https://safe-transaction-gnosis-chain.safe.global/";
  } else {
    throw new Error(`Unsupported network ${network}`);
  }
}

interface SafesAddressNoncesOutput {
  recommendedNonce: number;
}
// Once `@safe-global/api-kit` has been migrated from v1 to v2, this can be replaced with `getnextnonce`.
// <https://docs.safe.global/sdk-api-kit/reference#getnextnonce>
async function recommendedNonce(chainId: number, safeAddress: string) {
  // <https://safe-client.safe.global/index.html#/safes/SafesController_getNonces>
  const url = `https://safe-client.safe.global/v1/chains/${chainId.toString()}/safes/${safeAddress}/nonces`;
  const response = await fetch(url);
  const output: SafesAddressNoncesOutput = await response.json();
  return output.recommendedNonce;
}

// Creates and proposes a transaction to the Safe Multisig, which can then be confirmed by other signers in the Web UI. Returns the link to the transaction in the Web UI.
export async function proposeTransaction(
  { ethers }: HardhatRuntimeEnvironment,
  network: string,
  { authoringSafe, to, data }: Transaction,
): Promise<string> {
  const { chainId } = await ethers.provider.getNetwork();
  const [proposer] = await ethers.getSigners();
  const ethAdapter = new EthersAdapter({
    ethers,
    signerOrProvider: proposer,
  });
  let nonce;
  try {
    nonce = await recommendedNonce(chainId, authoringSafe);
  } catch {
    console.log("Unable to determine recommended nonce, using current one");
    nonce = undefined;
  }

  const safeTransactionData: SafeTransactionDataPartial = {
    to,
    data,
    value: "0",
    nonce,
  };

  const safeSdk = await Safe.create({ ethAdapter, safeAddress: authoringSafe });
  const safeTransaction = await safeSdk.createTransaction({
    safeTransactionData,
  });
  const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);
  const senderSignature = await safeSdk.signTransactionHash(safeTxHash);

  const safeService = new SafeApiKit({
    txServiceUrl: serviceUrlForNetwork(network),
    ethAdapter,
  });
  await safeService.proposeTransaction({
    safeAddress: authoringSafe,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: await proposer.getAddress(),
    senderSignature: senderSignature.data,
  });
  return `https://app.safe.global/transactions/tx?id=multisig_${authoringSafe}_${safeTxHash}&safe=${authoringSafe}`;
}
