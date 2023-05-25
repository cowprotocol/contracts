import axios from "axios";
import { Contract } from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { erc20Token, Erc20Token } from "./tokens";

// https://api.1inch.exchange/swagger/ethereum/#/Tokens/TokensController_getTokens
export type OneinchTokenList = Record<
  string,
  { symbol: string; decimals: number; address: string }
>;
export const ONEINCH_TOKENS: Promise<OneinchTokenList> = axios
  .get("https://api.1inch.exchange/v3.0/1/tokens")
  .then((response) => response.data.tokens)
  .catch(() => {
    console.log("Warning: unable to recover token list from 1inch");
    return {};
  });

export async function fastTokenDetails(
  address: string,
  hre: HardhatRuntimeEnvironment,
): Promise<Erc20Token | null> {
  const oneinchTokens = await ONEINCH_TOKENS;
  if (
    hre.network.name === "mainnet" &&
    oneinchTokens[address.toLowerCase()] !== undefined
  ) {
    const IERC20 = await hre.artifacts.readArtifact(
      "src/contracts/interfaces/IERC20.sol:IERC20",
    );
    const contract = new Contract(address, IERC20.abi, hre.ethers.provider);
    return { ...oneinchTokens[address.toLowerCase()], contract };
  }
  return erc20Token(address, hre);
}
