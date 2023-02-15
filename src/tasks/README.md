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
