export enum UserBalanceOpKind {
  DEPOSIT_INTERNAL = 0,
  WITHDRAW_INTERNAL = 1,
  TRANSFER_INTERNAL = 2,
  TRANSFER_EXTERNAL = 3,
}

export enum BalancerErrors {
  SWAP_LIMIT = "BAL#507",
  SWAP_DEADLINE = "BAL#508",
}
