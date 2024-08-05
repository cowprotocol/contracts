import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { BigNumberish, Contract, ContractReceipt } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import {
  Interaction,
  Order,
  OrderFlags,
  OrderKind,
  PRE_SIGNED,
  SettlementEncoder,
  SigningScheme,
  TradeExecution,
  TypedDataDomain,
  computeOrderUid,
  domain,
  normalizeInteractions,
  packOrderUidParams,
} from "../src/ts";

import { ceilDiv } from "./testHelpers";

describe("GPv2Settlement", () => {
  const [deployer, owner, ...traders] = waffle.provider.getWallets();

  let authenticator: Contract;
  let vault: MockContract;
  let settlement: Contract;
  let testDomain: TypedDataDomain;

  beforeEach(async () => {
    const GPv2AllowListAuthentication = await ethers.getContractFactory(
      "GPv2AllowListAuthentication",
      deployer,
    );
    authenticator = await GPv2AllowListAuthentication.deploy();
    await authenticator.initializeManager(owner.address);

    const IVault = await artifacts.readArtifact("IVault");
    vault = await waffle.deployMockContract(deployer, IVault.abi);

    const GPv2Settlement = await ethers.getContractFactory(
      "GPv2SettlementTestInterface",
      deployer,
    );
    settlement = await GPv2Settlement.deploy(
      authenticator.address,
      vault.address,
    );

    const { chainId } = await ethers.provider.getNetwork();
    testDomain = domain(chainId, settlement.address);
  });

  describe("computeTradeExecutions", () => {
    const sellToken = `0x${"11".repeat(20)}`;
    const buyToken = `0x${"22".repeat(20)}`;
    const prices = {
      [sellToken]: 1,
      [buyToken]: 2,
    };
    const partialOrder = {
      sellToken,
      buyToken,
      sellAmount: ethers.utils.parseEther("42"),
      buyAmount: ethers.utils.parseEther("13.37"),
      validTo: 0xffffffff,
      appData: 0,
      feeAmount: ethers.constants.Zero,
    };

    describe("Order Executed Amounts", () => {
      const { sellAmount, buyAmount } = partialOrder;
      const executedAmount = ethers.utils.parseEther("10.0");
      const computeSettlementForOrderVariant = async (
        {
          kind,
          partiallyFillable,
          ...orderOverrides
        }: OrderFlags & Partial<Order>,
        execution: TradeExecution = { executedAmount },
        clearingPrices: Record<string, BigNumberish> = prices,
      ) => {
        const encoder = new SettlementEncoder(testDomain);
        await encoder.signEncodeTrade(
          {
            ...partialOrder,
            kind,
            partiallyFillable,
            ...orderOverrides,
          },
          traders[0],
          SigningScheme.EIP712,
          execution,
        );

        const {
          inTransfers: [{ amount: executedSellAmount }],
          outTransfers: [{ amount: executedBuyAmount }],
        } = await settlement.callStatic.computeTradeExecutionsTest(
          encoder.tokens,
          encoder.clearingPrices(clearingPrices),
          encoder.trades,
        );

        const [sellPrice, buyPrice] = [
          clearingPrices[sellToken],
          clearingPrices[buyToken],
        ];

        return { executedSellAmount, sellPrice, executedBuyAmount, buyPrice };
      };

      it("should compute amounts for fill-or-kill sell orders", async () => {
        const { executedSellAmount, sellPrice, executedBuyAmount, buyPrice } =
          await computeSettlementForOrderVariant({
            kind: OrderKind.SELL,
            partiallyFillable: false,
          });

        expect(executedSellAmount).to.deep.equal(sellAmount);
        expect(executedBuyAmount).to.deep.equal(
          sellAmount.mul(sellPrice).div(buyPrice),
        );
      });

      it("should respect the limit price for fill-or-kill sell orders", async () => {
        const { executedBuyAmount } = await computeSettlementForOrderVariant({
          kind: OrderKind.SELL,
          partiallyFillable: false,
        });

        expect(executedBuyAmount.gt(buyAmount)).to.be.true;
      });

      it("should compute amounts for fill-or-kill buy orders", async () => {
        const { executedSellAmount, sellPrice, executedBuyAmount, buyPrice } =
          await computeSettlementForOrderVariant({
            kind: OrderKind.BUY,
            partiallyFillable: false,
          });

        expect(executedSellAmount).to.deep.equal(
          buyAmount.mul(buyPrice).div(sellPrice),
        );
        expect(executedBuyAmount).to.deep.equal(buyAmount);
      });

      it("should respect the limit price for fill-or-kill buy orders", async () => {
        const { executedSellAmount } = await computeSettlementForOrderVariant({
          kind: OrderKind.BUY,
          partiallyFillable: false,
        });

        expect(executedSellAmount.lt(sellAmount)).to.be.true;
      });

      it("should compute amounts for partially fillable sell orders", async () => {
        const { executedSellAmount, sellPrice, executedBuyAmount, buyPrice } =
          await computeSettlementForOrderVariant({
            kind: OrderKind.SELL,
            partiallyFillable: true,
          });

        expect(executedSellAmount).to.deep.equal(executedAmount);
        expect(executedBuyAmount).to.deep.equal(
          ceilDiv(executedAmount.mul(sellPrice), buyPrice),
        );
      });

      it("should respect the limit price for partially fillable sell orders", async () => {
        const { executedSellAmount, executedBuyAmount } =
          await computeSettlementForOrderVariant({
            kind: OrderKind.SELL,
            partiallyFillable: true,
          });

        expect(
          executedBuyAmount
            .mul(sellAmount)
            .gt(executedSellAmount.mul(buyAmount)),
        ).to.be.true;
      });

      it("should compute amounts for partially fillable buy orders", async () => {
        const { executedSellAmount, sellPrice, executedBuyAmount, buyPrice } =
          await computeSettlementForOrderVariant({
            kind: OrderKind.BUY,
            partiallyFillable: true,
          });

        expect(executedSellAmount).to.deep.equal(
          executedAmount.mul(buyPrice).div(sellPrice),
        );
        expect(executedBuyAmount).to.deep.equal(executedAmount);
      });

      it("should respect the limit price for partially fillable buy orders", async () => {
        const { executedSellAmount, executedBuyAmount } =
          await computeSettlementForOrderVariant({
            kind: OrderKind.BUY,
            partiallyFillable: true,
          });

        expect(
          executedBuyAmount
            .mul(sellAmount)
            .gt(executedSellAmount.mul(buyAmount)),
        ).to.be.true;
      });

      it("should round executed buy amount in favour of trader for partial fill sell orders", async () => {
        const { executedBuyAmount } = await computeSettlementForOrderVariant(
          {
            kind: OrderKind.SELL,
            partiallyFillable: true,
            sellAmount: ethers.utils.parseEther("100.0"),
            buyAmount: ethers.utils.parseEther("1.0"),
          },
          { executedAmount: 1 },
          {
            [sellToken]: 1,
            [buyToken]: 100,
          },
        );

        // NOTE: Buy token is 100x more valuable than the sell token, however,
        // selling just 1 atom of the less valuable token will still give the
        // trader 1 atom of the much more valuable buy token.
        expect(executedBuyAmount).to.deep.equal(ethers.constants.One);
      });

      it("should round executed sell amount in favour of trader for partial fill buy orders", async () => {
        const { executedSellAmount } = await computeSettlementForOrderVariant(
          {
            kind: OrderKind.BUY,
            partiallyFillable: true,
            sellAmount: ethers.utils.parseEther("1.0"),
            buyAmount: ethers.utils.parseEther("100.0"),
          },
          { executedAmount: 1 },
          {
            [sellToken]: 100,
            [buyToken]: 1,
          },
        );

        // NOTE: Sell token is 100x more valuable than the buy token. Buying
        // just 1 atom of the less valuable buy token is free for the trader.
        expect(executedSellAmount).to.deep.equal(ethers.constants.Zero);
      });

      describe("should revert if order is executed for a too large amount", () => {
        it("sell order", async () => {
          const encoder = new SettlementEncoder(testDomain);
          const executedAmount = partialOrder.sellAmount.add(1);
          await encoder.signEncodeTrade(
            {
              ...partialOrder,
              kind: OrderKind.SELL,
              partiallyFillable: true,
            },
            traders[0],
            SigningScheme.EIP712,
            { executedAmount },
          );

          await expect(
            settlement.computeTradeExecutionsTest(
              encoder.tokens,
              encoder.clearingPrices(prices),
              encoder.trades,
            ),
          ).to.be.revertedWith("GPv2: order filled");
        });

        it("already partially filled sell order", async () => {
          let encoder = new SettlementEncoder(testDomain);
          const initialExecutedAmount = partialOrder.sellAmount.div(2);
          expect(initialExecutedAmount).not.to.deep.equal(
            ethers.constants.Zero,
          );
          await encoder.signEncodeTrade(
            {
              ...partialOrder,
              kind: OrderKind.SELL,
              partiallyFillable: true,
            },
            traders[0],
            SigningScheme.EIP712,
            { executedAmount: initialExecutedAmount },
          );
          await settlement.computeTradeExecutionsTest(
            encoder.tokens,
            encoder.clearingPrices(prices),
            encoder.trades,
          );

          encoder = new SettlementEncoder(testDomain);
          const unfilledAmount = partialOrder.sellAmount.sub(
            initialExecutedAmount,
          );
          expect(initialExecutedAmount).not.to.deep.equal(
            ethers.constants.Zero,
          );
          await encoder.signEncodeTrade(
            {
              ...partialOrder,
              kind: OrderKind.SELL,
              partiallyFillable: true,
            },
            traders[0],
            SigningScheme.EIP712,
            { executedAmount: unfilledAmount.add(1) },
          );
          await expect(
            settlement.computeTradeExecutionsTest(
              encoder.tokens,
              encoder.clearingPrices(prices),
              encoder.trades,
            ),
          ).to.be.revertedWith("GPv2: order filled");
        });

        it("buy order", async () => {
          const encoder = new SettlementEncoder(testDomain);
          const executedAmount = partialOrder.buyAmount.add(1);
          await encoder.signEncodeTrade(
            {
              ...partialOrder,
              kind: OrderKind.BUY,
              partiallyFillable: true,
            },
            traders[0],
            SigningScheme.EIP712,
            { executedAmount },
          );

          await expect(
            settlement.computeTradeExecutionsTest(
              encoder.tokens,
              encoder.clearingPrices(prices),
              encoder.trades,
            ),
          ).to.be.revertedWith("GPv2: order filled");
        });
      });
    });

    describe("Order Executed Fees", () => {
      const { sellAmount, buyAmount } = partialOrder;
      const feeAmount = ethers.utils.parseEther("10");
      const { [sellToken]: sellPrice, [buyToken]: buyPrice } = prices;
      const computeExecutedTradeForOrderVariant = async (
        { kind, partiallyFillable }: OrderFlags,
        tradeExecution?: Partial<TradeExecution>,
      ) => {
        const encoder = new SettlementEncoder(testDomain);
        await encoder.signEncodeTrade(
          {
            ...partialOrder,
            feeAmount,
            kind,
            partiallyFillable,
          },
          traders[0],
          SigningScheme.EIP712,
          tradeExecution,
        );

        const {
          inTransfers: [{ amount: executedSellAmount }],
          outTransfers: [{ amount: executedBuyAmount }],
        } = await settlement.callStatic.computeTradeExecutionsTest(
          encoder.tokens,
          encoder.clearingPrices(prices),
          encoder.trades,
        );

        return { executedSellAmount, executedBuyAmount };
      };

      it("should add the full fee for fill-or-kill sell orders", async () => {
        const { executedSellAmount } =
          await computeExecutedTradeForOrderVariant({
            kind: OrderKind.SELL,
            partiallyFillable: false,
          });

        expect(executedSellAmount).to.deep.equal(sellAmount.add(feeAmount));
      });

      it("should add the full fee for fill-or-kill buy orders", async () => {
        const { executedSellAmount } =
          await computeExecutedTradeForOrderVariant({
            kind: OrderKind.BUY,
            partiallyFillable: false,
          });

        const expectedSellAmount = buyAmount.mul(buyPrice).div(sellPrice);
        expect(executedSellAmount).to.deep.equal(
          expectedSellAmount.add(feeAmount),
        );
      });

      it("should add portion of fees for partially filled sell orders", async () => {
        const executedAmount = sellAmount.div(3);
        const executedFee = feeAmount.div(3);

        const { executedSellAmount } =
          await computeExecutedTradeForOrderVariant(
            { kind: OrderKind.SELL, partiallyFillable: true },
            { executedAmount },
          );

        expect(executedSellAmount).to.deep.equal(
          executedAmount.add(executedFee),
        );
      });

      it("should add portion of fees for partially filled buy orders", async () => {
        const executedBuyAmount = buyAmount.div(4);
        const executedFee = feeAmount.div(4);

        const { executedSellAmount } =
          await computeExecutedTradeForOrderVariant(
            { kind: OrderKind.BUY, partiallyFillable: true },
            { executedAmount: executedBuyAmount },
          );

        const expectedSellAmount = executedBuyAmount
          .mul(buyPrice)
          .div(sellPrice);
        expect(executedSellAmount).to.deep.equal(
          expectedSellAmount.add(executedFee),
        );
      });
    });

    describe("Order Filled Amounts", () => {
      const { sellAmount, buyAmount } = partialOrder;
      const readOrderFilledAmountAfterProcessing = async (
        { kind, partiallyFillable }: OrderFlags,
        tradeExecution?: Partial<TradeExecution>,
      ) => {
        const order = {
          ...partialOrder,
          kind,
          partiallyFillable,
        };
        const encoder = new SettlementEncoder(testDomain);
        await encoder.signEncodeTrade(
          order,
          traders[0],
          SigningScheme.EIP712,
          tradeExecution,
        );

        await settlement.computeTradeExecutionsTest(
          encoder.tokens,
          encoder.clearingPrices(prices),
          encoder.trades,
        );

        const orderUid = computeOrderUid(testDomain, order, traders[0].address);
        const filledAmount = await settlement.filledAmount(orderUid);

        return filledAmount;
      };

      it("should fill the full sell amount for fill-or-kill sell orders", async () => {
        const filledAmount = await readOrderFilledAmountAfterProcessing({
          kind: OrderKind.SELL,
          partiallyFillable: false,
        });

        expect(filledAmount).to.deep.equal(sellAmount);
      });

      it("should fill the full buy amount for fill-or-kill buy orders", async () => {
        const filledAmount = await readOrderFilledAmountAfterProcessing({
          kind: OrderKind.BUY,
          partiallyFillable: false,
        });

        expect(filledAmount).to.deep.equal(buyAmount);
      });

      it("should fill the executed amount for partially filled sell orders", async () => {
        const executedSellAmount = sellAmount.div(3);
        const filledAmount = await readOrderFilledAmountAfterProcessing(
          { kind: OrderKind.SELL, partiallyFillable: true },
          { executedAmount: executedSellAmount },
        );

        expect(filledAmount).to.deep.equal(executedSellAmount);
      });

      it("should fill the executed amount for partially filled buy orders", async () => {
        const executedBuyAmount = buyAmount.div(4);
        const filledAmount = await readOrderFilledAmountAfterProcessing(
          { kind: OrderKind.BUY, partiallyFillable: true },
          { executedAmount: executedBuyAmount },
        );

        expect(filledAmount).to.deep.equal(executedBuyAmount);
      });
    });
  });

  describe("executeInteractions", () => {
    it("executes valid interactions", async () => {
      const EventEmitter = await ethers.getContractFactory("EventEmitter");
      const interactionParameters = [
        {
          target: await EventEmitter.deploy(),
          value: ethers.utils.parseEther("0.42"),
          number: 1,
        },
        {
          target: await EventEmitter.deploy(),
          value: ethers.utils.parseEther("0.1337"),
          number: 2,
        },
        {
          target: await EventEmitter.deploy(),
          value: ethers.constants.Zero,
          number: 3,
        },
      ];

      const uniqueContractAddresses = new Set(
        interactionParameters.map((params) => params.target.address),
      );
      expect(uniqueContractAddresses.size).to.equal(
        interactionParameters.length,
      );

      const interactions = interactionParameters.map(
        ({ target, value, number }) => ({
          target: target.address,
          value,
          callData: target.interface.encodeFunctionData("emitEvent", [number]),
        }),
      );

      // Note: make sure to send some Ether to the settlement contract so that
      // it can execute the interactions with values.
      await deployer.sendTransaction({
        to: settlement.address,
        value: ethers.utils.parseEther("1.0"),
      });

      const settled = settlement.executeInteractionsTest(interactions);
      const { events }: ContractReceipt = await (await settled).wait();

      // Note: all contracts were touched.
      for (const { target } of interactionParameters) {
        await expect(settled).to.emit(target, "Event");
      }
      await expect(settled).to.emit(settlement, "Interaction");

      const emitterEvents = (events || []).filter(
        ({ address }) => address !== settlement.address,
      );
      expect(emitterEvents.length).to.equal(interactionParameters.length);

      // Note: the execution order was respected.
      for (let i = 0; i < interactionParameters.length; i++) {
        const params = interactionParameters[i];
        const args = params.target.interface.decodeEventLog(
          "Event",
          emitterEvents[i].data,
        );

        expect(args.value).to.equal(params.value);
        expect(args.number).to.equal(params.number);
      }
    });

    it("reverts if any of the interactions reverts", async () => {
      const mockPass = await waffle.deployMockContract(deployer, [
        "function alwaysPasses()",
      ]);
      await mockPass.mock.alwaysPasses.returns();
      const mockRevert = await waffle.deployMockContract(deployer, [
        "function alwaysReverts()",
      ]);
      await mockRevert.mock.alwaysReverts.revertsWithReason("test error");

      await expect(
        settlement.executeInteractionsTest(
          normalizeInteractions([
            {
              target: mockPass.address,
              callData: mockPass.interface.encodeFunctionData("alwaysPasses"),
            },
            {
              target: mockRevert.address,
              callData:
                mockRevert.interface.encodeFunctionData("alwaysReverts"),
            },
          ]),
        ),
      ).to.be.revertedWith("test error");
    });

    it("should revert when target is vaultRelayer", async () => {
      const invalidInteraction: Interaction = {
        target: await settlement.vaultRelayer(),
        callData: [],
        value: 0,
      };

      await expect(
        settlement.executeInteractionsTest([invalidInteraction]),
      ).to.be.revertedWith("GPv2: forbidden interaction");
    });

    it("reverts if the settlement contract does not have sufficient Ether balance", async () => {
      const value = ethers.utils.parseEther("1000000.0");
      expect(value.gt(await ethers.provider.getBalance(settlement.address))).to
        .be.true;

      await expect(
        settlement.executeInteractionsTest(
          normalizeInteractions([
            {
              target: ethers.constants.AddressZero,
              value,
            },
          ]),
        ),
      ).to.be.reverted;
    });

    it("emits an Interaction event", async () => {
      const contract = await waffle.deployMockContract(deployer, [
        "function someFunction(bytes32 parameter)",
      ]);

      const value = ethers.utils.parseEther("1.0");
      const parameter = `0x${"ff".repeat(32)}`;

      await deployer.sendTransaction({ to: settlement.address, value });
      await contract.mock.someFunction.withArgs(parameter).returns();

      const tx = settlement.executeInteractionsTest([
        {
          target: contract.address,
          value,
          callData: contract.interface.encodeFunctionData("someFunction", [
            parameter,
          ]),
        },
      ]);
      await expect(tx)
        .to.emit(settlement, "Interaction")
        .withArgs(
          contract.address,
          value,
          contract.interface.getSighash("someFunction"),
        );
    });
  });

  describe("Order Refunds", () => {
    const orderUids = [
      packOrderUidParams({
        orderDigest: `0x${"11".repeat(32)}`,
        owner: traders[0].address,
        validTo: 0,
      }),
      packOrderUidParams({
        orderDigest: `0x${"22".repeat(32)}`,
        owner: traders[0].address,
        validTo: 0,
      }),
      packOrderUidParams({
        orderDigest: `0x${"33".repeat(32)}`,
        owner: traders[0].address,
        validTo: 0,
      }),
    ];

    const commonTests = (freeStorageFunction: string) => {
      const testFunction = `${freeStorageFunction}Test`;

      it("should revert if not called from an interaction", async () => {
        await expect(settlement[freeStorageFunction]([])).to.be.revertedWith(
          "not an interaction",
        );
      });

      it("should revert if the encoded order UIDs are malformed", async () => {
        const orderUid = packOrderUidParams({
          orderDigest: ethers.constants.HashZero,
          owner: ethers.constants.AddressZero,
          validTo: 0,
        });

        for (const malformedOrderUid of [
          ethers.utils.hexDataSlice(orderUid, 0, 55),
          ethers.utils.hexZeroPad(orderUid, 57),
        ]) {
          await expect(
            settlement[testFunction]([malformedOrderUid]),
          ).to.be.revertedWith("invalid uid");
        }
      });

      it("should revert if the order is still valid", async () => {
        const orderUid = packOrderUidParams({
          orderDigest: `0x${"42".repeat(32)}`,
          owner: traders[0].address,
          validTo: 0xffffffff,
        });

        await expect(settlement[testFunction]([orderUid])).to.be.revertedWith(
          "order still valid",
        );
      });
    };

    describe("freeFilledAmountStorage", () => {
      it("should set filled amount to 0 for all orders", async () => {
        for (const orderUid of orderUids) {
          await settlement.connect(traders[0]).invalidateOrder(orderUid);
          expect(await settlement.filledAmount(orderUid)).to.not.deep.equal(
            ethers.constants.Zero,
          );
        }

        await settlement.freeFilledAmountStorageTest(orderUids);
        for (const orderUid of orderUids) {
          expect(await settlement.filledAmount(orderUid)).to.equal(
            ethers.constants.Zero,
          );
        }
      });

      commonTests("freeFilledAmountStorage");
    });

    describe("freePreSignatureStorage", () => {
      it("should clear pre-signatures", async () => {
        for (const orderUid of orderUids) {
          await settlement.connect(traders[0]).setPreSignature(orderUid, true);
          expect(await settlement.preSignature(orderUid)).to.equal(PRE_SIGNED);
        }

        await settlement.freePreSignatureStorageTest(orderUids);
        for (const orderUid of orderUids) {
          expect(await settlement.preSignature(orderUid)).to.equal(
            ethers.constants.Zero,
          );
        }
      });

      commonTests("freePreSignatureStorage");
    });
  });
});
