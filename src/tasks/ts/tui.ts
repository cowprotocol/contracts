import readline from "readline";

import { HardhatRuntimeEnvironment } from "hardhat/types";

// Only a single readline interface should be available at each point in time.
// If more than one is created, then any input to stdin will be printed more
// than once to stdout.
export const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

export async function prompt(
  { network }: HardhatRuntimeEnvironment,
  message: string,
): Promise<boolean> {
  if (network.name === "hardhat") {
    // shortcut prompts in tests.
    return true;
  }

  const response = await new Promise<string>((resolve) =>
    rl.question(`${message} (y/N) `, (response) => resolve(response)),
  );
  return "y" === response.toLowerCase();
}

export interface TransactionLike {
  hash: string;
}

export function transactionUrl(
  { network }: HardhatRuntimeEnvironment,
  { hash }: TransactionLike,
): string {
  switch (network.name) {
    case "mainnet":
      return `https://etherscan.io/tx/${hash}`;
    case "rinkeby":
      return `https://rinkeby.etherscan.io/tx/${hash}`;
    case "goerli":
      return `https://goerli.etherscan.io/tx/${hash}`;
    case "xdai":
      return `https://blockscout.com/xdai/mainnet/tx/${hash}`;
    default:
      return hash;
  }
}
