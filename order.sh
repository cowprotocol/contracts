# sepolia
network=sepolia
WETH="0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14";
COW="0x0625aFB445C3B6B7B929342a04A22599fd5dBB59";

E15='000000000000000'
type='sellAfterFee'
npx hardhat place-order --network "$network" --api-url 'http://127.0.0.1:8080' --amount-atoms "1000$E15" --from "$WETH" --to "$COW" "$type"
