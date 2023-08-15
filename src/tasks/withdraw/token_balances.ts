import axios from "axios";

interface AddressInfoResponse {
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

export async function getTokensWithBalanceAbove(
  minValueUsd: string,
  settlementContract: string,
): Promise<string[]> {
  const response = await axios.get(
    `https://api.ethplorer.io/getAddressInfo/${settlementContract}?apiKey=freekey`,
  );
  if (response.status !== 200) {
    throw new Error(`Error getting tokens from ETHplorer ${response}`);
  }
  const result = [];
  const data = response.data as AddressInfoResponse;
  for (const token of data.tokens) {
    const tokenUsdValue =
      token.tokenInfo.price.rate *
      (token.balance / Math.pow(10, token.tokenInfo.decimals));
    if (tokenUsdValue > parseInt(minValueUsd)) {
      result.push(token.tokenInfo.address);
    }
  }
  return result;
}
