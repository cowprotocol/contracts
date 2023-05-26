import { Contract } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { EncodedSettlement } from "../../ts";
import { IGasEstimator } from "../ts/gas";
import { prompt } from "../ts/tui";

import { isSigner, SignerOrAddress } from "./signer";

export interface SubmitSettlementInput {
  dryRun: boolean;
  doNotPrompt?: boolean | undefined;
  hre: HardhatRuntimeEnvironment;
  settlementContract: Contract;
  solver: SignerOrAddress;
  requiredConfirmations?: number | undefined;
  gasEstimator: IGasEstimator;
  encodedSettlement: EncodedSettlement;
}
export async function submitSettlement({
  dryRun,
  doNotPrompt,
  hre,
  settlementContract,
  solver,
  requiredConfirmations,
  gasEstimator,
  encodedSettlement,
}: SubmitSettlementInput) {
  if (!isSigner(solver)) {
    const settlementData = settlementContract.interface.encodeFunctionData(
      "settle",
      encodedSettlement,
    );
    console.log("Settlement transaction:");
    console.log(`to:   ${settlementContract.address}`);
    console.log(`data: ${settlementData}`);
  } else if (
    !dryRun &&
    (doNotPrompt || (await prompt(hre, "Submit settlement?")))
  ) {
    console.log("Executing the withdraw transaction on the blockchain...");
    const response = await settlementContract
      .connect(solver)
      .settle(...encodedSettlement, await gasEstimator.txGasPrice());
    console.log(
      "Transaction submitted to the blockchain. Waiting for acceptance in a block...",
    );
    const receipt = await response.wait(requiredConfirmations);
    console.log(
      `Transaction successfully executed. Transaction hash: ${receipt.transactionHash}`,
    );
  }
}
