import { expect } from "chai";
import { Contract } from "ethers";
import { ethers } from "hardhat";

import {
  OrderBalance,
  OrderKind,
  SigningScheme,
  encodeOrderFlags,
  encodeSigningScheme,
} from "../src/ts";

import {
  OrderBalanceId,
  decodeOrderKind,
  decodeOrderBalance,
} from "./encoding";

describe("GPv2Trade", () => {
  let tradeLib: Contract;

  beforeEach(async () => {
    const GPv2Trade = await ethers.getContractFactory("GPv2TradeTestInterface");

    tradeLib = await GPv2Trade.deploy();
  });

  describe("extractFlags", () => {
    it("should extract all supported order flags", async () => {
      const flagVariants = [OrderKind.SELL, OrderKind.BUY].flatMap((kind) =>
        [false, true].flatMap((partiallyFillable) =>
          [
            OrderBalance.ERC20,
            OrderBalance.EXTERNAL,
            OrderBalance.INTERNAL,
          ].flatMap((sellTokenBalance) =>
            [OrderBalance.ERC20, OrderBalance.INTERNAL].map(
              (buyTokenBalance) => ({
                kind,
                partiallyFillable,
                sellTokenBalance,
                buyTokenBalance,
              }),
            ),
          ),
        ),
      );

      for (const flags of flagVariants) {
        const {
          kind: encodedKind,
          partiallyFillable,
          sellTokenBalance: encodedSellTokenBalance,
          buyTokenBalance: encodedBuyTokenBalance,
        } = await tradeLib.extractFlagsTest(encodeOrderFlags(flags));
        expect({
          kind: decodeOrderKind(encodedKind),
          partiallyFillable,
          sellTokenBalance: decodeOrderBalance(encodedSellTokenBalance),
          buyTokenBalance: decodeOrderBalance(encodedBuyTokenBalance),
        }).to.deep.equal(flags);
      }
    });

    it("should accept 0b00 and 0b01 for ERC20 sell token balance flag", async () => {
      for (const encodedFlags of [0b00000, 0b00100]) {
        const { sellTokenBalance } = await tradeLib.extractFlagsTest(
          encodedFlags,
        );
        expect(sellTokenBalance).to.equal(OrderBalanceId.ERC20);
      }
    });

    it("should extract all supported signing schemes", async () => {
      for (const scheme of [
        SigningScheme.EIP712,
        SigningScheme.ETHSIGN,
        SigningScheme.EIP1271,
        SigningScheme.PRESIGN,
      ]) {
        const { signingScheme: extractedScheme } =
          await tradeLib.extractFlagsTest(encodeSigningScheme(scheme));
        expect(extractedScheme).to.deep.equal(scheme);
      }
    });

    it("should revert when encoding invalid flags", async () => {
      await expect(tradeLib.extractFlagsTest(0b10000000)).to.be.reverted;
    });
  });
});
