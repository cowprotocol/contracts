import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";

import { subtask, task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getDeployedContract } from "./ts/deployment";
import { getNamedSigner } from "./ts/signers";
import { getSolvers } from "./ts/solver";
import { transactionUrl } from "./ts/tui";

const solversTaskList = [
  "add",
  "check",
  "remove",
  "list",
  "setManager",
] as const;
type SolversTasks = (typeof solversTaskList)[number];

interface Args {
  address?: string;
  printTransaction: boolean;
}

async function addSolver(args: Args, hre: HardhatRuntimeEnvironment) {
  await performSolverManagement("addSolver", args, hre);
}

const removeSolver = async (args: Args, hre: HardhatRuntimeEnvironment) => {
  await performSolverManagement("removeSolver", args, hre);
};

const setManager = async (args: Args, hre: HardhatRuntimeEnvironment) => {
  await performSolverManagement("setManager", args, hre);
};

async function performSolverManagement(
  method: "addSolver" | "removeSolver" | "setManager",
  { address, printTransaction }: Args,
  hre: HardhatRuntimeEnvironment,
): Promise<void> {
  const authenticator = await getDeployedContract(
    "GPv2AllowListAuthentication",
    hre,
  );

  if (printTransaction) {
    const data = authenticator.interface.encodeFunctionData(method, [address]);
    console.log(`\`${method}\` transaction:`);
    console.log(`To:   ${authenticator.address}`);
    console.log(`Data: ${data}`);
  } else {
    const owner = await getNamedSigner(hre, "manager");
    const tx = await authenticator.connect(owner)[method](address);
    console.log(transactionUrl(hre, tx));
    await tx.wait();
    console.log(`Executed \`${method}\`.`);
  }
}

const isSolver = async (solver: string, hre: HardhatRuntimeEnvironment) => {
  const authenticator = await getDeployedContract(
    "GPv2AllowListAuthentication",
    hre,
  );

  console.log(
    `${solver} is ${
      (await authenticator.isSolver(solver)) ? "" : "NOT "
    }a solver.`,
  );
};

async function listSolvers(hre: HardhatRuntimeEnvironment) {
  const authenticator = await getDeployedContract(
    "GPv2AllowListAuthentication",
    hre,
  );

  console.log((await getSolvers(authenticator)).join("\n"));
}

const setupSolversTask: () => void = () => {
  task(
    "solvers",
    "Reads and changes the state of the authenticator in CoW Protocol.",
  )
    .addPositionalParam<SolversTasks>(
      "subtask",
      `The action to execute on the authenticator. Allowed subtasks: ${solversTaskList.join(
        ", ",
      )}`,
    )
    .addOptionalPositionalParam<string>(
      "address",
      "The solver account to add, remove, or check",
    )
    .addFlag(
      "printTransaction",
      "Prints the transaction to standard out when adding or removing solvers.",
    )
    .setAction(async (taskArguments, { run }) => {
      const { subtask } = taskArguments;
      if (solversTaskList.includes(subtask)) {
        delete taskArguments.subtask;
        await run(`solvers-${subtask}`, taskArguments);
      } else {
        throw new Error(`Invalid solver subtask ${subtask}.`);
      }
    });

  subtask(
    "solvers-add",
    "Adds a solver to the list of allowed solvers in GPv2.",
  )
    .addPositionalParam<string>("address", "The solver account to add.")
    .addFlag("printTransaction", "Prints the transaction to standard out.")
    .setAction(addSolver);

  subtask(
    "solvers-remove",
    "Removes a solver from the list of allowed solvers in GPv2.",
  )
    .addPositionalParam<string>("address", "The solver account to remove.")
    .addFlag("printTransaction", "Prints the transaction to standard out.")
    .setAction(removeSolver);

  subtask(
    "solvers-setManager",
    "Changes the manager who is responsible to add and remove solvers.",
  )
    .addPositionalParam<string>(
      "address",
      "The address that is going to replace the current manager.",
    )
    .addFlag("printTransaction", "Prints the transaction to standard out.")
    .setAction(setManager);

  subtask(
    "solvers-check",
    "Checks that an address is registered as a solver of GPv2.",
  )
    .addPositionalParam<string>("address", "The solver account to check.")
    .setAction(async ({ address }, hardhatRuntime) => {
      await isSolver(address, hardhatRuntime);
    });

  subtask(
    "solvers-list",
    "List all currently registered solvers of GPv2.",
  ).setAction(async (_, hardhatRuntime) => {
    await listSolvers(hardhatRuntime);
  });
};

export { setupSolversTask };
