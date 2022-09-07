import { promises as fs } from "fs";

import "@nomiclabs/hardhat-ethers";
import { Contract } from "ethers";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { SettlementEncoder } from "../ts";

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
  // Instantiate Settlement Contract
  const settlementDeployment = await hre.deployments.get("GPv2Settlement");
  const settlement = new Contract(
    settlementDeployment.address,
    settlementDeployment.abi,
  ).connect(hre.ethers.provider);
  const [signer] = await hre.ethers.getSigners();

  //Instantiate ERC20 ABI
  const IERC20 = await hre.artifacts.readArtifact(
    "src/contracts/interfaces/IERC20.sol:IERC20",
  );
  const token = new Contract(
    hre.ethers.constants.AddressZero,
    IERC20.abi,
    hre.ethers.provider,
  );

  // Load approval list and encode interaction for each entry
  const approvals: Approval[] = JSON.parse(await fs.readFile(input, "utf-8"));
  const encoder = new SettlementEncoder({});
  approvals.forEach((approval) => {
    encoder.encodeInteraction({
      target: approval.token,
      callData: token.interface.encodeFunctionData("approve", [
        approval.spender,
        hre.ethers.constants.MaxUint256,
      ]),
    });
  });
  const finalSettlement = encoder.encodedSettlement({});
  const gasEstimator = createGasEstimator(hre, {
    blockNative: true,
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
      "Fix a gas price instead of using the blockscout gas estimator",
      0,
      types.int,
    )
    .setAction(setApprovals);
};

export { setupSetApprovalsTask };
