import SafeApiKit from "@safe-global/api-kit";
import Safe, { EthersAdapter } from "@safe-global/protocol-kit";
import { HardhatRuntimeEnvironment } from "hardhat/types";

interface Transaction {
  authoringSafe: string;
  to: string;
  data: string;
}

function serviceUrlForNetwork(network: string): string {
  if (["goerli", "mainnet", "gnosis-chain"].includes(network)) {
    return `https://safe-transaction-${network}.safe.global`;
  } else if (network === "xdai") {
    return "https://safe-transaction-gnosis-chain.safe.global/";
  } else {
    throw new Error(`Unsupported network ${network}`);
  }
}

// Creates and proposes a transaction to the Safe Multisig, which can then be confirmed by other signers in the Web UI. Returns the link to the transaction in the Web UI.
export async function proposeTransaction(
  { ethers }: HardhatRuntimeEnvironment,
  network: string,
  { authoringSafe, to, data }: Transaction,
): Promise<string> {
  const [proposer] = await ethers.getSigners();
  const ethAdapter = new EthersAdapter({
    ethers,
    signerOrProvider: proposer,
  });

  const safeTransactionData = {
    to,
    data,
    value: "0",
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
