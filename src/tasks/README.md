# Hardhat tasks

Below a description of how to run some of the scripts in this folder:

## setApprovals

Set PK and NODE_URL env variables. Create a json with with a list of desired allowances (use 0 to revoke allowance) such as:

```json
[
  {
    "spender": "0x9008d19f58aabd9ed0d60971565aa8510560ab41",
    "token": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    "amount": "0"
  }
]
```

Then run

```
yarn hardhat set-approvals --network <network> --gas-in-gwei <gas_price> [--dry-run] <path to json>
```

## selfSell

Creates partially fillable limit orders in the name of the settlement contract, which can be used to swap and withdraw accrued fees or internal buffers.

Set PK and NODE_URL env variables. Then run something like

```
npx hardhat self-sell \
  --network mainnet \
  --receiver 0xA03be496e67Ec29bC62F01a428683D7F9c204930 \
  --to-token 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
  --min-value 900 \
  --leftover 100 \
  --fee-slippage-bps 10000 \
  --price-slippage-bps 500 \
  --max-fee-percent 10 \
  --validity 7200 \
  --api-url "https://api.cow.fi/mainnet"
```

if the transaction is initiated by a Safe, add the `origin <address>` and `safe` flag to make it automatically propose a tranasction (`PK` needs to be a signer on the safe). If you specify `--notify-slack-channel <channel>` it will also send a slack message asking for signatures (`SLACK_TOKEN` needs to be exported as an env variable).
