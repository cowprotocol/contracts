import { BigNumber, utils } from "ethers";

import { displayName, Erc20Token, NativeToken } from "../ts/tokens";
import { formatUsdValue, ReferenceToken } from "../ts/value";

export function ignoredTokenMessage(
  [token, amount]: [Erc20Token | NativeToken, BigNumber],
  reason?: string,
  asUsd?: [ReferenceToken, BigNumber],
) {
  const decimals = token.decimals ?? 18;
  let message = `Ignored ${utils.formatUnits(
    amount,
    decimals,
  )} units of ${displayName(token)}${
    token.decimals === undefined
      ? ` (no decimals specified in the contract, assuming ${decimals})`
      : ""
  }`;
  if (asUsd !== undefined) {
    const [usdReference, valueUsd] = asUsd;
    message += ` with value ${formatUsdValue(valueUsd, usdReference)} USD`;
  }
  if (reason !== undefined) {
    message += `, ${reason}`;
  }
  return message;
}
