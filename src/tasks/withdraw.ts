import "@nomiclabs/hardhat-ethers";

import chalk from "chalk";
import { BigNumber, constants, Contract, utils } from "ethers";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { EncodedSettlement, SettlementEncoder } from "../ts";
import {
  Api,
  ApiError,
  CallError,
  Environment,
  LIMIT_CONCURRENT_REQUESTS,
} from "../ts/api";

import {
  getDeployedContract,
  isSupportedNetwork,
  SupportedNetwork,
} from "./ts/deployment";
import { createGasEstimator, IGasEstimator } from "./ts/gas";
import {
  DisappearingLogFunctions,
  promiseAllWithRateLimit,
} from "./ts/rate_limits";
import { getSolvers } from "./ts/solver";
import { Align, displayTable } from "./ts/table";
import { erc20Token, Erc20Token } from "./ts/tokens";
import {
  formatTokenValue,
  formatUsdValue,
  REFERENCE_TOKEN,
  ReferenceToken,
  usdValue,
  usdValueOfEth,
  formatGasCost,
} from "./ts/value";
import { ignoredTokenMessage } from "./withdraw/messages";
import { submitSettlement } from "./withdraw/settle";
import { getSignerOrAddress, SignerOrAddress } from "./withdraw/signer";
import { getAllTradedTokens } from "./withdraw/traded_tokens";

interface Withdrawal {
  token: Erc20Token;
  amount: BigNumber;
  amountUsd: BigNumber;
  balance: BigNumber;
  balanceUsd: BigNumber;
  gas: BigNumber;
}

interface DisplayWithdrawal {
  symbol: string;
  balance: string;
  amount: string;
  value: string;
  address: string;
}

interface ComputeSettlementInput {
  withdrawals: Omit<Withdrawal, "gas">[];
  receiver: string;
  solverForSimulation: string;
  settlement: Contract;
  hre: HardhatRuntimeEnvironment;
}
async function computeSettlement({
  withdrawals,
  receiver,
  solverForSimulation,
  settlement,
  hre,
}: ComputeSettlementInput) {
  const encoder = new SettlementEncoder({});
  withdrawals.forEach(({ token, amount }) =>
    encoder.encodeInteraction({
      target: token.address,
      callData: token.contract.interface.encodeFunctionData("transfer", [
        receiver,
        amount,
      ]),
    }),
  );

  const finalSettlement = encoder.encodedSettlement({});
  const gas = await settlement
    .connect(hre.ethers.provider)
    .estimateGas.settle(...finalSettlement, {
      from: solverForSimulation,
    });
  return {
    finalSettlement,
    gas,
  };
}

interface ComputeSettlementWithPriceInput extends ComputeSettlementInput {
  gasPrice: BigNumber;
  network: SupportedNetwork;
  usdReference: ReferenceToken;
  api: Api;
}
async function computeSettlementWithPrice({
  withdrawals,
  receiver,
  solverForSimulation,
  settlement,
  gasPrice,
  network,
  usdReference,
  api,
  hre,
}: ComputeSettlementWithPriceInput) {
  const { gas, finalSettlement } = await computeSettlement({
    withdrawals,
    receiver,
    solverForSimulation,
    settlement,
    hre,
  });

  const transactionEthCost = gas.mul(gasPrice);
  // The following ternary operator is used as a hack to avoid having to
  // set expectations for the gas value in the tests, since gas values
  // could easily change with any minor changes to the tests
  const transactionUsdCost =
    hre.network.name === "hardhat"
      ? constants.Zero
      : await usdValueOfEth(transactionEthCost, usdReference, network, api);
  const withdrawnValue = withdrawals.reduce(
    (sum, { amountUsd }) => sum.add(amountUsd),
    constants.Zero,
  );

  return {
    finalSettlement,
    transactionEthCost,
    transactionUsdCost,
    gas,
    withdrawnValue,
  };
}

export interface GetBalanceToWithdrawInput {
  token: Erc20Token;
  usdReference: ReferenceToken;
  settlement: Contract;
  api: Api;
  leftoverWei: BigNumber;
  minValueWei: BigNumber;
  consoleLog: typeof console.log;
}
export interface BalanceOutput {
  netAmount: BigNumber;
  netAmountUsd: BigNumber;
  balance: BigNumber;
  balanceUsd: BigNumber;
}
export async function getAmounts({
  token,
  usdReference,
  settlement,
  api,
  leftoverWei,
  minValueWei,
  consoleLog,
}: GetBalanceToWithdrawInput): Promise<BalanceOutput | null> {
  const balance = await token.contract.balanceOf(settlement.address);
  if (balance.eq(0)) {
    return null;
  }
  let balanceUsd;
  try {
    balanceUsd = await usdValue(token.address, balance, usdReference, api);
  } catch (e) {
    if (!(e instanceof Error)) {
      throw e;
    }
    const errorData: ApiError = (e as CallError).apiError ?? {
      errorType: "script internal error",
      description: e?.message ?? "no details",
    };
    consoleLog(
      `Warning: price retrieval failed for token ${token.symbol} (${token.address}): ${errorData.errorType} (${errorData.description})`,
    );
    balanceUsd = constants.Zero;
  }
  // Note: if balanceUsd is zero, then setting either minValue or leftoverWei
  // to a nonzero value means that nothing should be withdrawn. If neither
  // flag is set, then whether to withdraw does not depend on the USD value.
  if (
    balanceUsd.lt(minValueWei.add(leftoverWei)) ||
    (balanceUsd.isZero() && !(minValueWei.isZero() && leftoverWei.isZero()))
  ) {
    consoleLog(
      ignoredTokenMessage(
        [token, balance],
        "does not satisfy conditions on min value and leftover",
        [usdReference, balanceUsd],
      ),
    );
    return null;
  }
  let netAmount;
  let netAmountUsd;
  if (balanceUsd.isZero()) {
    // Note: minValueWei and leftoverWei are zero. Everything should be
    // withdrawn.
    netAmount = balance;
    netAmountUsd = balanceUsd;
  } else {
    netAmount = balance.mul(balanceUsd.sub(leftoverWei)).div(balanceUsd);
    netAmountUsd = balanceUsd.sub(leftoverWei);
  }
  return { netAmount, netAmountUsd, balance, balanceUsd };
}

interface GetWithdrawalsInput {
  tokens: string[];
  settlement: Contract;
  minValue: string;
  leftover: string;
  gasEmptySettlement: Promise<BigNumber>;
  hre: HardhatRuntimeEnvironment;
  usdReference: ReferenceToken;
  receiver: string;
  solverForSimulation: string;
  api: Api;
}
async function getWithdrawals({
  tokens,
  settlement,
  minValue,
  leftover,
  gasEmptySettlement,
  hre,
  usdReference,
  receiver,
  solverForSimulation,
  api,
}: GetWithdrawalsInput): Promise<Withdrawal[]> {
  const minValueWei = utils.parseUnits(minValue, usdReference.decimals);
  const leftoverWei = utils.parseUnits(leftover, usdReference.decimals);
  const computeWithdrawalInstructions = tokens.map(
    (tokenAddress) =>
      async ({ consoleLog }: DisappearingLogFunctions) => {
        const token = await erc20Token(tokenAddress, hre);
        if (token === null) {
          throw new Error(
            `There is no valid ERC20 token at address ${tokenAddress}`,
          );
        }

        const amounts = await getAmounts({
          token,
          usdReference,
          settlement,
          api,
          leftoverWei,
          minValueWei,
          consoleLog,
        });
        if (amounts === null) {
          return null;
        }

        const withdrawalWithoutGas = {
          token,
          amount: amounts.netAmount,
          amountUsd: amounts.netAmountUsd,
          balance: amounts.balance,
          balanceUsd: amounts.balanceUsd,
        };
        let gas;
        try {
          ({ gas } = await computeSettlement({
            withdrawals: [withdrawalWithoutGas],
            receiver,
            solverForSimulation,
            settlement,
            hre,
          }));
        } catch (error) {
          if (!(error instanceof Error)) {
            throw error;
          }
          consoleLog(
            ignoredTokenMessage(
              [token, amounts.balance],
              `cannot execute withdraw transaction (${error.message})`,
              [usdReference, amounts.balanceUsd],
            ),
          );
          return null;
        }
        return {
          ...withdrawalWithoutGas,
          gas: gas.sub(await gasEmptySettlement),
        };
      },
  );
  const processedWithdrawals: (Withdrawal | null)[] =
    await promiseAllWithRateLimit(computeWithdrawalInstructions, {
      message: "computing withdrawals",
      rateLimit: LIMIT_CONCURRENT_REQUESTS,
    });
  return processedWithdrawals.filter(
    (withdrawal) => withdrawal !== null,
  ) as Withdrawal[];
}

function formatWithdrawal(
  withdrawal: Withdrawal,
  usdReference: ReferenceToken,
): DisplayWithdrawal {
  const formatDecimals = withdrawal.token.decimals ?? 18;
  return {
    address: withdrawal.token.address,
    value: formatUsdValue(withdrawal.balanceUsd, usdReference),
    balance: formatTokenValue(withdrawal.balance, formatDecimals, 18),
    amount: formatTokenValue(withdrawal.amount, formatDecimals, 18),
    symbol: withdrawal.token.symbol ?? "unknown token",
  };
}

function displayWithdrawals(
  withdrawals: Withdrawal[],
  usdReference: ReferenceToken,
) {
  const formattedWithdtrawals = withdrawals.map((w) =>
    formatWithdrawal(w, usdReference),
  );
  const order = ["address", "value", "balance", "amount", "symbol"] as const;
  const header = {
    address: "address",
    value: "balance (usd)",
    balance: "balance",
    amount: "withdrawn amount",
    symbol: "symbol",
  };
  console.log(chalk.bold("Amounts to withdraw:"));
  displayTable(header, formattedWithdtrawals, order, {
    value: { align: Align.Right },
    balance: { align: Align.Right, maxWidth: 30 },
    amount: { align: Align.Right, maxWidth: 30 },
    symbol: { maxWidth: 20 },
  });
  console.log();
}

interface WithdrawInput {
  solver: SignerOrAddress;
  tokens: string[] | undefined;
  minValue: string;
  leftover: string;
  maxFeePercent: number;
  receiver: string;
  authenticator: Contract;
  settlement: Contract;
  settlementDeploymentBlock: number;
  network: SupportedNetwork;
  usdReference: ReferenceToken;
  hre: HardhatRuntimeEnvironment;
  api: Api;
  dryRun: boolean;
  gasEstimator: IGasEstimator;
  doNotPrompt?: boolean | undefined;
  requiredConfirmations?: number | undefined;
}

async function prepareWithdrawals({
  solver,
  tokens,
  minValue,
  leftover,
  maxFeePercent,
  receiver,
  authenticator,
  settlement,
  settlementDeploymentBlock,
  network,
  usdReference,
  hre,
  api,
  dryRun,
  gasEstimator,
}: WithdrawInput): Promise<{
  withdrawals: Withdrawal[];
  finalSettlement: EncodedSettlement | null;
}> {
  let solverForSimulation: string;
  if (await authenticator.isSolver(solver.address)) {
    solverForSimulation = solver.address;
  } else {
    const message =
      "Current account is not a solver. Only a solver can withdraw funds from the settlement contract.";
    if (!dryRun) {
      throw Error(message);
    } else {
      solverForSimulation = (await getSolvers(authenticator))[0];
      console.log(message);
      if (solverForSimulation === undefined) {
        throw new Error(
          `There are no valid solvers for network ${network}, withdrawing is not possible`,
        );
      }
    }
  }
  const gasEmptySettlement = computeSettlement({
    withdrawals: [],
    receiver,
    solverForSimulation,
    settlement,
    hre,
  }).then(({ gas }) => gas);

  if (tokens === undefined) {
    console.log("Recovering list of traded tokens...");
    ({ tokens } = await getAllTradedTokens(
      settlement,
      settlementDeploymentBlock,
      "latest",
      hre,
    ));
  }

  // TODO: add eth withdrawal
  // TODO: split large transaction in batches
  let withdrawals = await getWithdrawals({
    tokens,
    settlement,
    minValue,
    leftover,
    gasEmptySettlement,
    hre,
    usdReference,
    receiver,
    solverForSimulation,
    api,
  });
  withdrawals.sort((lhs, rhs) => {
    const diff = lhs.balanceUsd.sub(rhs.balanceUsd);
    return diff.isZero() ? 0 : diff.isNegative() ? -1 : 1;
  });

  const oneEth = utils.parseEther("1");
  const [oneEthUsdValue, gasPrice] = await Promise.all([
    usdValueOfEth(oneEth, usdReference, network, api),
    gasEstimator.gasPriceEstimate(),
  ]);
  withdrawals = withdrawals.filter(
    ({ token, balance, balanceUsd, amountUsd, gas }) => {
      const approxUsdValue = Number(amountUsd.toString());
      const approxGasCost = Number(
        gasPrice.mul(gas).mul(oneEthUsdValue).div(oneEth),
      );
      const feePercent = (100 * approxGasCost) / approxUsdValue;
      if (feePercent > maxFeePercent) {
        console.log(
          ignoredTokenMessage(
            [token, balance],
            `the gas cost is too high (${feePercent.toFixed(
              2,
            )}% of the withdrawn amount)`,
            [usdReference, balanceUsd],
          ),
        );
        return false;
      }

      return true;
    },
  );

  if (withdrawals.length === 0) {
    console.log("No tokens to withdraw.");
    return { withdrawals: [], finalSettlement: null };
  }
  displayWithdrawals(withdrawals, usdReference);

  const {
    finalSettlement,
    transactionEthCost,
    transactionUsdCost,
    withdrawnValue,
  } = await computeSettlementWithPrice({
    withdrawals,
    receiver,
    gasPrice,
    solverForSimulation,
    settlement,
    network,
    usdReference,
    api,
    hre,
  });

  console.log(
    `The transaction will cost approximately ${formatGasCost(
      transactionEthCost,
      transactionUsdCost,
      network,
      usdReference,
    )} and will withdraw the balance of ${
      withdrawals.length
    } tokens for an estimated total value of ${formatUsdValue(
      withdrawnValue,
      usdReference,
    )} USD. All withdrawn funds will be sent to ${receiver}.`,
  );

  return { withdrawals, finalSettlement };
}

export async function withdraw(input: WithdrawInput): Promise<string[] | null> {
  let withdrawals, finalSettlement;
  try {
    ({ withdrawals, finalSettlement } = await prepareWithdrawals(input));
  } catch (error) {
    console.log(
      "Script failed execution but no irreversible operations were performed",
    );
    console.log(error);
    return null;
  }

  if (finalSettlement === null) {
    return [];
  }

  await submitSettlement({
    ...input,
    settlementContract: input.settlement,
    encodedSettlement: finalSettlement,
  });

  return withdrawals.map((w) => w.token.address);
}

const setupWithdrawTask: () => void = () =>
  task("withdraw", "Withdraw funds from the settlement contract")
    .addOptionalParam(
      "origin",
      "Address from which to withdraw. If not specified, it defaults to the first provided account",
    )
    .addOptionalParam(
      "minValue",
      "If specified, sets a minimum USD value required to withdraw the balance of a token.",
      "0",
      types.string,
    )
    .addOptionalParam(
      "leftover",
      "If specified, withdrawing leaves an amount of each token of USD value specified with this flag.",
      "0",
      types.string,
    )
    .addOptionalParam(
      "maxFeePercent",
      "If the extra gas needed to include a withdrawal is larger than this percent of the withdrawn amount, the token is not withdrawn.",
      5,
      types.float,
    )
    .addOptionalParam(
      "apiUrl",
      "If set, the script contacts the API using the given url. Otherwise, the default prod url for the current network is used",
    )
    .addParam("receiver", "The address receiving the withdrawn tokens.")
    .addFlag(
      "dryRun",
      "Just simulate the settlement instead of executing the transaction on the blockchain.",
    )
    .addFlag(
      "blocknativeGasPrice",
      "Use BlockNative gas price estimates for transactions.",
    )
    .addOptionalVariadicPositionalParam(
      "tokens",
      "An optional subset of tokens to consider for withdraw (otherwise all traded tokens will be queried).",
    )
    .setAction(
      async (
        {
          origin,
          minValue,
          leftover,
          maxFeePercent,
          receiver: inputReceiver,
          dryRun,
          tokens,
          apiUrl,
          blocknativeGasPrice,
        },
        hre: HardhatRuntimeEnvironment,
      ) => {
        const network = hre.network.name;
        if (!isSupportedNetwork(network)) {
          throw new Error(`Unsupported network ${network}`);
        }
        const gasEstimator = createGasEstimator(hre, {
          blockNative: blocknativeGasPrice,
        });
        const api = new Api(network, apiUrl ?? Environment.Prod);
        const receiver = utils.getAddress(inputReceiver);
        const [authenticator, settlementDeployment, solver] = await Promise.all(
          [
            getDeployedContract("GPv2AllowListAuthentication", hre),
            hre.deployments.get("GPv2Settlement"),
            getSignerOrAddress(hre, origin),
          ],
        );
        const settlement = new Contract(
          settlementDeployment.address,
          settlementDeployment.abi,
        ).connect(hre.ethers.provider);
        const settlementDeploymentBlock =
          settlementDeployment.receipt?.blockNumber ?? 0;
        console.log(`Using account ${solver.address}`);

        await withdraw({
          solver,
          tokens,
          minValue,
          leftover,
          receiver,
          maxFeePercent,
          authenticator,
          settlement,
          settlementDeploymentBlock,
          network,
          usdReference: REFERENCE_TOKEN[network],
          hre,
          api,
          dryRun,
          gasEstimator,
        });
      },
    );

export { setupWithdrawTask };
