import axios from "axios";

interface AddressInfoResponse {
  tokens: Token[]
}

interface Token {
  tokenInfo: TokenInfo;
  balance: number;
}

interface TokenInfo {
  address: string;
  decimals: number;
  price: TokenPrice;
}

interface TokenPrice {
  rate: number;
}

export async function getTokensWithBalanceAbove(minValueUsd: string, settlementContract: string) {
  const response = await axios.get(`https://api.ethplorer.io/getAddressInfo/${settlementContract}?apiKey=freekey`);
  if (response.status !== 200) {
    console.log(`Error getting tokens from ETHplorer ${response}`)
  }
  const result = []
  const data = response.data as AddressInfoResponse;
  for (const token of data.tokens)  {
    const tokenUsdValue = token.tokenInfo.price.rate * (token.balance / Math.pow(10, token.tokenInfo.decimals))
    if (tokenUsdValue > parseInt(minValueUsd)) {
      result.push(token.tokenInfo.address)
    }
  }
  return result;
}
