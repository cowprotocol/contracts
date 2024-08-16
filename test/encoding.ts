import { BigNumber } from "ethers";
import { ethers } from "hardhat";

import { Order, OrderBalance, OrderKind } from "../src/ts";

type AbiOrder = [
  string,
  string,
  string,
  BigNumber,
  BigNumber,
  number,
  string,
  BigNumber,
  string,
  boolean,
  string,
  string,
];

function decodeEnum<T>(hash: string, values: T[]): T {
  for (const value of values) {
    if (hash == ethers.utils.id(`${value}`)) {
      return value;
    }
  }
  throw new Error(`invalid enum hash '${hash}'`);
}

export function decodeOrderKind(kindHash: string): OrderKind {
  return decodeEnum(kindHash, [OrderKind.SELL, OrderKind.BUY]);
}

export function decodeOrderBalance(balanceHash: string): OrderBalance {
  return decodeEnum(balanceHash, [
    OrderBalance.ERC20,
    OrderBalance.EXTERNAL,
    OrderBalance.INTERNAL,
  ]);
}

export function decodeOrder(order: AbiOrder): Order {
  return {
    sellToken: order[0],
    buyToken: order[1],
    receiver: order[2],
    sellAmount: order[3],
    buyAmount: order[4],
    validTo: order[5],
    appData: order[6],
    feeAmount: order[7],
    kind: decodeOrderKind(order[8]),
    partiallyFillable: order[9],
    sellTokenBalance: decodeOrderBalance(order[10]),
    buyTokenBalance: decodeOrderBalance(order[11]),
  };
}
