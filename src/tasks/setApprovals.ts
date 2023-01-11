import { promises as fs } from "fs";

import "@nomiclabs/hardhat-ethers";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { SettlementEncoder } from "../ts";

import { getDeployedContract } from "./ts/deployment";
import { createGasEstimator, gweiToWei } from "./ts/gas";
import { prompt } from "./ts/tui";

interface Approval {
  spender: string;
  token: string;
}

interface Args {
  input: string;
  dryRun: boolean;
  gasInGwei: number;
}

async function setApprovals(
  { input, dryRun, gasInGwei }: Args,
  hre: HardhatRuntimeEnvironment,
) {
  const settlement = await getDeployedContract("GPv2Settlement", hre);
  const [signer] = await hre.ethers.getSigners();

  //Instantiate ERC20 ABI
  const IERC20 = await hre.artifacts.readArtifact(
    "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20",
  );
  const token = new hre.ethers.utils.Interface(IERC20.abi);

  // Load approval list and encode interaction for each entry
  const approvals: Approval[] = JSON.parse(await fs.readFile(input, "utf-8"));
  const encoder = new SettlementEncoder({});
  approvals.forEach((approval) => {
    encoder.encodeInteraction({
      target: approval.token,
      callData: token.encodeFunctionData("approve", [
        approval.spender,
        hre.ethers.constants.MaxUint256,
      ]),
    });
  });
  const finalSettlement = encoder.encodedSettlement({});
  const gasEstimator = createGasEstimator(hre, {
    blockNative: false,
  });
  const gasPrice =
    gasInGwei > 0
      ? {
          maxFeePerGas: gweiToWei(gasInGwei),
          maxPriorityFeePerGas: gweiToWei(gasInGwei),
        }
      : await gasEstimator.txGasPrice();

  // settle the transaction
  if (
    !dryRun &&
    (await prompt(hre, `Submit with gas price ${gasPrice.maxFeePerGas}?`))
  ) {
    const response = await settlement
      .connect(signer)
      .settle(...finalSettlement, gasPrice);
    console.log(
      "Transaction submitted to the blockchain. Waiting for acceptance in a block...",
    );
    const receipt = await response.wait(1);
    console.log(
      `Transaction successfully executed. Transaction hash: ${receipt.transactionHash}`,
    );
  } else {
    const settlementData = settlement.interface.encodeFunctionData(
      "settle",
      finalSettlement,
    );
    console.log(settlementData);
  }
}

const setupSetApprovalsTask: () => void = () => {
  task(
    "set-approvals",
    "Given a file containing a list of tokens and spenders, sets allowances on behalf of the settlement contract",
  )
    .addPositionalParam<string>(
      "input",
      `A json file containing a list of entries with token and spender field`,
    )
    .addFlag(
      "dryRun",
      "Just simulate the settlement instead of executing the transaction on the blockchain.",
    )
    .addOptionalParam(
      "gasInGwei",
      "Fix a gas price instead of using the native gas estimator",
      0,
      types.int,
    )
    .setAction(setApprovals);
};

export { setupSetApprovalsTask };
