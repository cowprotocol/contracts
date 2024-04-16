import axios from "axios";

export interface GetTokensInput {
  minValueUsd: number;
  settlementContract: string;
  chainId: number;
}

export async function getTokensWithBalanceAbove({
  minValueUsd,
  settlementContract,
  chainId,
}: GetTokensInput): Promise<string[]> {
  switch (chainId) {
    case 1:
      return await getMainnetTokensWithBalanceAbove(
        minValueUsd,
        settlementContract,
      );
    case 100:
      return await getGnosisChainTokensWithBalanceAbove(
        minValueUsd,
        settlementContract,
      );
    default:
      throw new Error(
        `Automatic token list generation is not supported on chain with id ${chainId}`,
      );
  }
}

interface EthplorerAddressInfoResponse {
  tokens: {
    tokenInfo: {
      address: string;
      decimals: number;
      price: {
        rate: number;
      };
    };
    balance: number;
  }[];
}

export async function getMainnetTokensWithBalanceAbove(
  minValueUsd: number,
  settlementContract: string,
): Promise<string[]> {
  const response = await axios.get(
    `https://api.ethplorer.io/getAddressInfo/${settlementContract}?apiKey=freekey`,
  );
  if (response.status !== 200) {
    throw new Error(`Error getting tokens from ETHplorer ${response}`);
  }
  const result = [];
  const data = response.data as EthplorerAddressInfoResponse;
  for (const token of data.tokens) {
    const tokenUsdValue =
      token.tokenInfo.price.rate *
      (token.balance / Math.pow(10, token.tokenInfo.decimals));
    if (tokenUsdValue > minValueUsd) {
      result.push(token.tokenInfo.address);
    }
  }
  return result;
}

type BlockscoutAddressInfoResponse = BlockscoutSingleTokenInfo[];
interface BlockscoutSingleTokenInfo {
  token: {
    address: string;
    exchange_rate: string;
    decimals: string;
  };
  value: string;
}

export async function getGnosisChainTokensWithBalanceAbove(
  minValueUsd: number,
  settlementContract: string,
): Promise<string[]> {
  const response = await axios.get(
    `https://gnosis.blockscout.com/api/v2/addresses/${settlementContract}/token-balances`,
  );
  if (response.status !== 200) {
    throw new Error(`Error getting tokens from ETHplorer ${response}`);
  }
  const result = [];
  const data = response.data as BlockscoutAddressInfoResponse;
  for (const { value, token } of data) {
    const tokenUsdValue =
      parseFloat(token.exchange_rate) *
      (parseInt(value) / Math.pow(10, parseInt(token.decimals)));
    if (tokenUsdValue > minValueUsd) {
      result.push(token.address);
    }
  }
  return result;
}
