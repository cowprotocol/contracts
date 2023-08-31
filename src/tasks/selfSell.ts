import "@nomiclabs/hardhat-ethers";

import chalk from "chalk";
import { BigNumber, constants, Contract, TypedDataDomain, utils } from "ethers";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import {
  BUY_ETH_ADDRESS,
  computeOrderUid,
  domain,
  EncodedSettlement,
  Order,
  OrderKind,
  PreSignSignature,
  SettlementEncoder,
  SigningScheme,
} from "../ts";
import {
  Api,
  CallError,
  Environment,
  LIMIT_CONCURRENT_REQUESTS,
} from "../ts/api";

import {
  assertNotBuyingNativeAsset,
  getQuote,
  computeValidTo,
  APP_DATA,
  MAX_ORDER_VALIDITY_SECONDS,
  Quote,
} from "./dump";
import {
  getDeployedContract,
  isSupportedNetwork,
  SupportedNetwork,
} from "./ts/deployment";
import { createGasEstimator, IGasEstimator } from "./ts/gas";
import { fastTokenDetails } from "./ts/oneinch_tokens";
import {
  DisappearingLogFunctions,
  promiseAllWithRateLimit,
} from "./ts/rate_limits";
import { getSolvers } from "./ts/solver";
import { Align, displayTable } from "./ts/table";
import { Erc20Token, erc20Token } from "./ts/tokens";
import { prompt } from "./ts/tui";
import {
  formatTokenValue,
  formatUsdValue,
  REFERENCE_TOKEN,
  ReferenceToken,
  usdValue,
  usdValueOfEth,
  formatGasCost,
} from "./ts/value";
import { BalanceOutput, getAmounts } from "./withdraw";
import { ignoredTokenMessage } from "./withdraw/messages";
import { proposeTransaction } from "./withdraw/safe";
import { submitSettlement } from "./withdraw/settle";
import { getSignerOrAddress, SignerOrAddress } from "./withdraw/signer";
import { sendSlackMessage } from "./withdraw/slack";
import { getTokensWithBalanceAbove } from "./withdraw/token_balances";
import { getAllTradedTokens } from "./withdraw/traded_tokens";

interface DisplayOrder {
  symbol: string;
  balance: string;
  sellAmount: string;
  sellAmountUsd: string;
  address: string;
  buyAmount: string;
  feePercent: string;
  needsAllowance: "yes" | "";
}

interface ComputeSettlementInput {
  orders: Pick<OrderDetails, "sellToken" | "orderUid" | "needsAllowance">[];
  solverForSimulation: string;
  settlement: Contract;
  vaultRelayer: string;
  hre: HardhatRuntimeEnvironment;
}
async function computeSettlement({
  orders,
  solverForSimulation,
  settlement,
  vaultRelayer,
  hre,
}: ComputeSettlementInput) {
  const encoder = new SettlementEncoder({});
  for (const order of orders) {
    if (order.needsAllowance) {
      encoder.encodeInteraction({
        target: order.sellToken.address,
        callData: order.sellToken.contract.interface.encodeFunctionData(
          "approve",
          [vaultRelayer, constants.MaxUint256],
        ),
      });
    }
    encoder.encodeInteraction({
      target: settlement.address,
      callData: settlement.interface.encodeFunctionData("setPreSignature", [
        order.orderUid,
        true,
      ]),
    });
  }

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

interface ComputeSettlementWithPriceInput
  extends Omit<ComputeSettlementInput, "orders"> {
  orders: OrderDetails[];
  gasPrice: BigNumber;
  network: SupportedNetwork;
  usdReference: ReferenceToken;
  api: Api;
}
async function computeSettlementWithPrice({
  orders,
  solverForSimulation,
  settlement,
  vaultRelayer,
  gasPrice,
  network,
  usdReference,
  api,
  hre,
}: ComputeSettlementWithPriceInput) {
  const { gas, finalSettlement } = await computeSettlement({
    orders,
    solverForSimulation,
    settlement,
    vaultRelayer,
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
  const soldValue = orders.reduce(
    (sum, { sellAmountUsd }) => sum.add(sellAmountUsd),
    constants.Zero,
  );

  return {
    finalSettlement,
    transactionEthCost,
    transactionUsdCost,
    gas,
    soldValue,
  };
}

interface ComputeOrderAfterFeeSlippageInput {
  quote: Quote;
  amounts: BalanceOutput;
  feeSlippageBps: number;
  receiver: string;
  usdReference: ReferenceToken;
  sellToken: Erc20Token;
  validTo: number;
}
function computeOrderAfterFeeSlippage({
  quote,
  amounts,
  feeSlippageBps,
  receiver,
  usdReference,
  sellToken,
  validTo,
}: ComputeOrderAfterFeeSlippageInput): {
  order: Order;
  adjustedFee: BigNumber;
} | null {
  // Tentatively adjust the fee linearly assuming that the order's exchange rate
  // doesn't depend on the amount.

  // Fee amounts are taken from the sell token. We need to reserve the following
  // extra amount because it could be taken by a gas price increase:
  const reservedSellAmountForFeeSlippage = quote.feeAmount
    .mul(feeSlippageBps)
    .div(10000);

  const fullSellAmount = quote.sellAmount.add(quote.feeAmount);
  // We take this extra fee from the buy amount, since the full sell amount is
  // fixed.
  const reservedBuyAmountForFeeSlippage = reservedSellAmountForFeeSlippage
    .mul(quote.buyAmount)
    .div(fullSellAmount);

  if (reservedBuyAmountForFeeSlippage.gte(quote.buyAmount)) {
    console.log(
      ignoredTokenMessage(
        [sellToken, amounts.balance],
        `adjusting order for fee slippage requires more than what is obtained from selling`,
        [usdReference, amounts.balanceUsd],
      ),
    );
    return null;
  }

  return {
    order: {
      sellToken: quote.sellToken,
      buyToken: quote.buyToken,
      receiver,
      sellAmount: fullSellAmount,
      buyAmount: quote.buyAmount.sub(reservedBuyAmountForFeeSlippage),
      validTo,
      appData: APP_DATA,
      feeAmount: constants.Zero,
      kind: OrderKind.SELL,
      partiallyFillable: true,
    },
    adjustedFee: quote.feeAmount.add(reservedSellAmountForFeeSlippage),
  };
}

interface OrderDetails {
  order: Order;
  sellAmountUsd: BigNumber;
  feeUsd: BigNumber;
  balance: BigNumber;
  balanceUsd: BigNumber;
  sellToken: Erc20Token;
  orderUid: string;
  needsAllowance: boolean;
  extraGas: BigNumber;
}

interface GetOrdersInput {
  tokens: string[];
  toToken: Erc20Token;
  settlement: Contract;
  vaultRelayer: string;
  minValue: string;
  leftover: string;
  maxFeePercent: number;
  priceSlippageBps: number;
  feeSlippageBps: number;
  validity: number;
  hre: HardhatRuntimeEnvironment;
  usdReference: ReferenceToken;
  receiver: string;
  api: Api;
  domainSeparator: TypedDataDomain;
  solverForSimulation: string;
}
async function getOrders({
  tokens,
  toToken,
  settlement,
  vaultRelayer,
  minValue,
  leftover,
  maxFeePercent,
  priceSlippageBps,
  feeSlippageBps,
  validity,
  hre,
  usdReference,
  receiver,
  api,
  domainSeparator,
  solverForSimulation,
}: GetOrdersInput): Promise<OrderDetails[]> {
  const minValueWei = utils.parseUnits(minValue, usdReference.decimals);
  const leftoverWei = utils.parseUnits(leftover, usdReference.decimals);
  const gasEmptySettlement = computeSettlement({
    orders: [],
    solverForSimulation,
    settlement,
    vaultRelayer,
    hre,
  }).then(({ gas }) => gas);

  const computeOrderInstructions = tokens.map(
    (tokenAddress) =>
      async ({ consoleLog }: DisappearingLogFunctions) => {
        const sellToken = await fastTokenDetails(tokenAddress, hre);
        if (sellToken === null) {
          throw new Error(
            `There is no valid ERC20 token at address ${tokenAddress}`,
          );
        }

        const amounts = await getAmounts({
          token: sellToken,
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

        let allowance;
        try {
          allowance = BigNumber.from(
            await sellToken.contract.allowance(
              settlement.address,
              vaultRelayer,
            ),
          );
        } catch (e) {
          consoleLog(
            ignoredTokenMessage(
              [sellToken, amounts.balance],
              "cannot determine size of vault relayer allowance",
            ),
          );
          return null;
        }
        const needsAllowance = allowance.lt(amounts.netAmount);

        const validTo = computeValidTo(validity);
        const owner = settlement.address;
        const quote = await getQuote({
          sellToken,
          buyToken: toToken,
          api,
          sellAmountBeforeFee: amounts.netAmount,
          maxFeePercent,
          slippageBps: priceSlippageBps,
          validTo,
          user: owner,
        });
        if (quote === null) {
          return null;
        }
        const adjustedOrder = computeOrderAfterFeeSlippage({
          quote,
          amounts,
          feeSlippageBps,
          receiver,
          usdReference,
          sellToken,
          validTo,
        });
        if (adjustedOrder === null) {
          return null;
        }
        const { order, adjustedFee } = adjustedOrder;
        const orderUid = computeOrderUid(domainSeparator, order, owner);

        let feeUsd;
        try {
          feeUsd = await usdValue(
            order.sellToken,
            adjustedFee,
            usdReference,
            api,
          );
        } catch (error) {
          if (!(error instanceof Error)) {
            throw error;
          }
          consoleLog(
            ignoredTokenMessage(
              [sellToken, amounts.balance],
              `cannot determine USD value of fee (${error.message})`,
              [usdReference, amounts.balanceUsd],
            ),
          );
          return null;
        }

        const extraGas = (
          await computeSettlement({
            orders: [
              {
                needsAllowance,
                orderUid,
                sellToken,
              },
            ],
            solverForSimulation,
            settlement,
            vaultRelayer,
            hre,
          })
        ).gas.sub(await gasEmptySettlement);

        return {
          order,
          feeUsd,
          sellAmountUsd: amounts.netAmountUsd,
          balance: amounts.balance,
          balanceUsd: amounts.balanceUsd,
          sellToken,
          owner: settlement.address,
          orderUid,
          needsAllowance,
          extraGas,
        };
      },
  );
  const processedOrders: (OrderDetails | null)[] =
    await promiseAllWithRateLimit(computeOrderInstructions, {
      message: "retrieving available tokens",
      rateLimit: LIMIT_CONCURRENT_REQUESTS,
    });
  return processedOrders.filter((order) => order !== null) as OrderDetails[];
}

function formatOrder(
  order: OrderDetails,
  toToken: Erc20Token,
  usdReference: ReferenceToken,
): DisplayOrder {
  const formatSellTokenDecimals = order.sellToken.decimals ?? 18;
  const formatBuyTokenDecimals = toToken.decimals ?? 18;
  const feePercentBps = order.feeUsd.mul(10000).div(order.sellAmountUsd);
  const feePercent = feePercentBps.lt(1)
    ? "<0.01"
    : utils.formatUnits(feePercentBps, 2);
  return {
    address: order.sellToken.address,
    sellAmountUsd: formatUsdValue(order.balanceUsd, usdReference),
    balance: formatTokenValue(order.balance, formatSellTokenDecimals, 10),
    sellAmount: formatTokenValue(
      BigNumber.from(order.order.sellAmount),
      formatSellTokenDecimals,
      10,
    ),
    symbol: order.sellToken.symbol ?? "unknown token",
    buyAmount: formatTokenValue(
      BigNumber.from(order.order.buyAmount),
      formatBuyTokenDecimals,
      10,
    ),
    feePercent,
    needsAllowance: order.needsAllowance ? "yes" : "",
  };
}

function displayOrders(
  orders: OrderDetails[],
  usdReference: ReferenceToken,
  toToken: Erc20Token,
) {
  const formattedOrders = orders.map((o) =>
    formatOrder(o, toToken, usdReference),
  );
  const orderWithoutAllowances = [
    "address",
    "sellAmountUsd",
    "balance",
    "sellAmount",
    "symbol",
    "buyAmount",
    "feePercent",
  ] as const;
  const order = orders.some((o) => o.needsAllowance)
    ? ([...orderWithoutAllowances, "needsAllowance"] as const)
    : orderWithoutAllowances;
  const header = {
    address: "address",
    sellAmountUsd: "value (USD)",
    balance: "balance",
    sellAmount: "sold amount",
    symbol: "symbol",
    buyAmount: `buy amount${toToken.symbol ? ` (${toToken.symbol})` : ""}`,
    feePercent: "fee %",
    needsAllowance: "needs allowance?",
  };
  console.log(chalk.bold("Amounts to sell:"));
  displayTable(header, formattedOrders, order, {
    sellAmountUsd: { align: Align.Right },
    balance: { align: Align.Right, maxWidth: 30 },
    sellAmount: { align: Align.Right, maxWidth: 30 },
    symbol: { maxWidth: 20 },
    buyAmount: { align: Align.Right, maxWidth: 30 },
  });
  console.log();
}

interface SelfSellInput {
  solver: SignerOrAddress;
  tokens: string[] | undefined;
  toToken: string;
  minValue: string;
  leftover: string;
  maxFeePercent: number;
  priceSlippageBps: number;
  feeSlippageBps: number;
  validity: number;
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
  domainSeparator: TypedDataDomain;
  solverIsSafe: boolean;
  notifySlackChannel?: string;
}

async function prepareOrders({
  solver,
  tokens,
  toToken: toTokenAddress,
  minValue,
  leftover,
  maxFeePercent,
  validity,
  priceSlippageBps,
  feeSlippageBps,
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
  domainSeparator,
}: SelfSellInput): Promise<{
  orders: OrderDetails[];
  finalSettlement: EncodedSettlement | null;
}> {
  const vaultRelayer: Promise<string> = settlement.vaultRelayer();

  let solverForSimulation: string;
  if (await authenticator.isSolver(solver.address)) {
    solverForSimulation = solver.address;
  } else {
    const message =
      "Current account is not a solver. Only a solver can execute `settle` in the settlement contract.";
    if (!dryRun) {
      throw Error(message);
    } else {
      solverForSimulation = (await getSolvers(authenticator))[0];
      console.log(message);
      if (solverForSimulation === undefined) {
        throw new Error(
          `There are no valid solvers for network ${network}, settlements are not possible`,
        );
      }
    }
  }

  if (tokens === undefined) {
    console.log("Recovering list of traded tokens...");
    ({ tokens } = await getAllTradedTokens(
      settlement,
      settlementDeploymentBlock,
      "latest",
      hre,
    ));
  }

  // TODO: remove once native asset orders are fully supported.
  assertNotBuyingNativeAsset(toTokenAddress);
  // todo: support dumping ETH by wrapping them
  if (tokens.includes(BUY_ETH_ADDRESS)) {
    throw new Error(
      `Dumping the native token is not supported. Remove the ETH flag address ${BUY_ETH_ADDRESS} from the list of tokens to dump.`,
    );
  }
  const erc20 = await erc20Token(toTokenAddress, hre);
  if (erc20 === null) {
    throw new Error(
      `Input toToken at address ${toTokenAddress} is not a valid Erc20 token.`,
    );
  }
  const toToken: Erc20Token = erc20;

  // TODO: send same token to receiver
  if (tokens.includes(toToken.address)) {
    throw new Error(
      `Selling toToken is not yet supported. Remove ${toToken.address} from the list of tokens to dump.`,
    );
  }

  // TODO: add eth orders
  // TODO: split large transaction in batches
  let orders = await getOrders({
    tokens,
    toToken,
    settlement,
    vaultRelayer: await vaultRelayer,
    minValue,
    leftover,
    hre,
    usdReference,
    receiver,
    api,
    validity,
    maxFeePercent,
    priceSlippageBps,
    feeSlippageBps,
    domainSeparator,
    solverForSimulation,
  });
  orders.sort((lhs, rhs) => {
    const diff = BigNumber.from(lhs.order.buyAmount).sub(rhs.order.buyAmount);
    return diff.isZero() ? 0 : diff.isNegative() ? -1 : 1;
  });

  const oneEth = utils.parseEther("1");
  const [oneEthUsdValue, gasPrice] = await Promise.all([
    usdValueOfEth(oneEth, usdReference, network, api),
    gasEstimator.gasPriceEstimate(),
  ]);
  // Note: we don't add the gas fee when generating `orders` because we want to
  // fetch gas prices at the last possible time to limit gas fluctuations.
  orders = orders.map((o) => {
    const marginalGasCost = gasPrice
      .mul(o.extraGas)
      .mul(oneEthUsdValue)
      .div(oneEth);
    return { ...o, feeUsd: o.feeUsd.add(marginalGasCost) };
  });
  orders = orders.filter(
    ({ feeUsd, sellAmountUsd, sellToken, balance, balanceUsd }) => {
      const approxUsdValue = Number(sellAmountUsd.toString());
      const approxTotalFee = Number(feeUsd);
      const feePercent = (100 * approxTotalFee) / approxUsdValue;
      if (feePercent > maxFeePercent) {
        console.log(
          ignoredTokenMessage(
            [sellToken, balance],
            `gas plus trade fee is too high (${feePercent.toFixed(
              2,
            )}% of the traded amount)`,
            [usdReference, balanceUsd],
          ),
        );
        return false;
      }

      return true;
    },
  );

  if (orders.length === 0) {
    console.log("No tokens to sell.");
    return { orders: [], finalSettlement: null };
  }
  displayOrders(orders, usdReference, toToken);

  const { finalSettlement, transactionEthCost, transactionUsdCost, soldValue } =
    await computeSettlementWithPrice({
      orders,
      gasPrice,
      solverForSimulation,
      settlement,
      vaultRelayer: await vaultRelayer,
      network,
      usdReference,
      api,
      hre,
    });

  console.log(
    `The settlement transaction will cost approximately ${formatGasCost(
      transactionEthCost,
      transactionUsdCost,
      network,
      usdReference,
    )} and will create ${
      orders.length
    } orders for an estimated total value of ${formatUsdValue(
      soldValue,
      usdReference,
    )} USD. The proceeds of the orders will be sent to ${receiver}.`,
  );

  return { orders, finalSettlement };
}

interface SubmitOrderToApiInput {
  orders: OrderDetails[];
  settlement: Contract;
  api: Api;
  hre: HardhatRuntimeEnvironment;
  dryRun: boolean;
  doNotPrompt?: boolean;
}
async function submitOrdersToApi({
  orders,
  settlement,
  hre,
  api,
  dryRun,
  doNotPrompt,
}: SubmitOrderToApiInput) {
  if (
    dryRun ||
    !(doNotPrompt || (await prompt(hre, "Submit orders to API?")))
  ) {
    return;
  }

  const from = settlement.address;
  const preSignSignature: PreSignSignature = {
    scheme: SigningScheme.PRESIGN,
    data: from,
  };
  for (const order of orders) {
    console.log(
      `Posting order selling ${
        order.sellToken.symbol ?? order.sellToken.address
      }...`,
    );
    try {
      const apiOrderUid = await api.placeOrder({
        order: order.order,
        signature: preSignSignature,
        from,
      });
      console.log(`Successfully created order with uid ${apiOrderUid}`);
      if (apiOrderUid != order.orderUid) {
        throw new Error(
          "CoW Swap API returns different orderUid than what is used to presign the order. This order will not be settled and the code should be checked for bugs.",
        );
      }
    } catch (error) {
      if (
        error instanceof Error &&
        (error as CallError)?.apiError !== undefined
      ) {
        // not null because of the condition in the if statement above
        // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
        const { errorType, description } = (error as CallError).apiError!;
        console.error(
          `Failed submitting order selling ${
            order.sellToken.symbol ?? order.sellToken.address
          }, the server returns ${errorType} (${description})`,
        );
        console.error(`Order details: ${JSON.stringify(order)}`);
      } else {
        throw error;
      }
    }
  }
}

export async function selfSell(input: SelfSellInput): Promise<string[] | null> {
  let orders, finalSettlement;
  try {
    ({ orders, finalSettlement } = await prepareOrders(input));
  } catch (error) {
    console.error(
      "Script failed execution but no irreversible operations were performed",
    );
    console.error(error);
    throw error;
  }

  if (finalSettlement === null) {
    return [];
  }

  await submitOrdersToApi({
    orders,
    settlement: input.settlement,
    api: input.api,
    hre: input.hre,
    dryRun: input.dryRun,
    doNotPrompt: input.doNotPrompt,
  });

  if (input.dryRun) {
    console.log("Not sending transaction in dryRun mode");
  } else if (input.solverIsSafe) {
    const settlementData = input.settlement.interface.encodeFunctionData(
      "settle",
      finalSettlement,
    );
    const safeTxUrl = await proposeTransaction(
      input.hre,
      input.hre.network.name,
      {
        to: input.settlement.address,
        data: settlementData,
        authoringSafe: input.solver.address,
      },
    );
    console.log(`Sign settlement transaction in the Safe UI: ${safeTxUrl}`);
    if (input.notifySlackChannel) {
      await sendSlackMessage(input.notifySlackChannel, safeTxUrl);
    }
  } else {
    await submitSettlement({
      ...input,
      settlementContract: input.settlement,
      encodedSettlement: finalSettlement,
    });
  }

  return orders.map((o) => o.sellToken.address);
}

const setupSelfSellTask: () => void = () =>
  task(
    "self-sell",
    "Sets up sell orders for the entire balance of the specified tokens from the settlement contract",
  )
    .addOptionalParam(
      "origin",
      "Address from which to create the orders. If not specified, it defaults to the first provided account",
    )
    .addOptionalParam(
      "minValue",
      "If specified, sets a minimum USD value required to sell the balance of a token.",
      "0",
      types.string,
    )
    .addOptionalParam(
      "leftover",
      "If specified, selling leaves an amount of each token of USD value specified with this flag.",
      "0",
      types.string,
    )
    .addOptionalParam(
      "validity",
      `How long the sell orders will be valid after their creation in seconds. It cannot be larger than ${MAX_ORDER_VALIDITY_SECONDS}`,
      20 * 60,
      types.int,
    )
    .addOptionalParam(
      "feeSlippageBps",
      "The slippage in basis points to account for changes in the trading fees between when the order is created and when it's executed by CoW Swap",
      1000,
      types.int,
    )
    .addOptionalParam(
      "priceSlippageBps",
      "The slippage in basis points for selling the dumped tokens",
      10,
      types.int,
    )
    .addOptionalParam(
      "maxFeePercent",
      "If the fees involved in creating a sell order (gas & trading fees) are larger than this percent of the sold amount, the token is not sold.",
      5,
      types.float,
    )
    .addOptionalParam(
      "apiUrl",
      "If set, the script contacts the API using the given url. Otherwise, the default prod url for the current network is used",
    )
    .addParam("receiver", "The receiver of the sold tokens.")
    .addFlag(
      "dryRun",
      "Just simulate the settlement instead of executing the transaction on the blockchain.",
    )
    .addFlag(
      "doNotPrompt",
      "Automatically propose/execute the transaction without asking for confirmation.",
    )
    .addFlag(
      "blocknativeGasPrice",
      "Use BlockNative gas price estimates for transactions.",
    )
    .addOptionalParam(
      "toToken",
      "All input tokens will be dumped to this token. If not specified, it defaults to the network's native token (e.g., ETH)",
    )
    .addFlag(
      "safe",
      "Whether the solver is a Safe and the script should propose the transaction to the Safe UI instead of sending a transaction directly",
    )
    .addOptionalParam(
      "notifySlackChannel",
      "The slack channel id to send the proposed transaction to (requires SLACK_TOKEN env variable to be set)",
    )
    .setAction(
      async (
        {
          origin,
          toToken,
          minValue,
          leftover,
          maxFeePercent,
          priceSlippageBps,
          feeSlippageBps,
          validity,
          receiver: inputReceiver,
          dryRun,
          apiUrl,
          blocknativeGasPrice,
          safe,
          notifySlackChannel,
          doNotPrompt,
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
        const [authenticator, settlementDeployment, solver, chainId] =
          await Promise.all([
            getDeployedContract("GPv2AllowListAuthentication", hre),
            hre.deployments.get("GPv2Settlement"),
            getSignerOrAddress(hre, origin),
            hre.ethers.provider.getNetwork().then((n) => n.chainId),
          ]);
        const settlement = new Contract(
          settlementDeployment.address,
          settlementDeployment.abi,
        ).connect(hre.ethers.provider);
        const settlementDeploymentBlock =
          settlementDeployment.receipt?.blockNumber ?? 0;
        const domainSeparator = domain(chainId, settlement.address);
        console.log(`Using account ${solver.address}`);

        if (validity > MAX_ORDER_VALIDITY_SECONDS) {
          throw new Error("Order validity too large");
        }

        // Exclude the toToken if needed, as we can not sell it for itself (buyToken is not allowed to equal sellToken)
        const tokens = (
          await getTokensWithBalanceAbove(
            minValue,
            settlementDeployment.address,
          )
        ).filter(
          (token) => utils.getAddress(token) != utils.getAddress(toToken),
        );

        await selfSell({
          solver,
          tokens,
          toToken,
          minValue,
          leftover,
          receiver,
          maxFeePercent,
          priceSlippageBps,
          feeSlippageBps,
          validity,
          authenticator,
          settlement,
          settlementDeploymentBlock,
          network,
          usdReference: REFERENCE_TOKEN[network],
          hre,
          api,
          dryRun,
          gasEstimator,
          domainSeparator,
          solverIsSafe: safe,
          notifySlackChannel,
          doNotPrompt,
        });
      },
    );

export { setupSelfSellTask };
