import IERC20 from "@openzeppelin/contracts/build/contracts/IERC20.json";
import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { Contract, ContractReceipt } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import {
  Interaction,
  OrderBalance,
  OrderFlags,
  OrderKind,
  PRE_SIGNED,
  SettlementEncoder,
  SigningScheme,
  SwapEncoder,
  SwapExecution,
  TradeExecution,
  TypedDataDomain,
  computeOrderUid,
  domain,
  normalizeInteractions,
  packOrderUidParams,
} from "../src/ts";

import { SwapKind, UserBalanceOpKind } from "./balancer";

function fillBytes(count: number, byte: number): string {
  return ethers.utils.hexlify([...Array(count)].map(() => byte));
}

describe("GPv2Settlement", () => {
  const [deployer, owner, solver, ...traders] = waffle.provider.getWallets();

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

  describe("swap", () => {
    let alwaysSuccessfulTokens: [Contract, Contract];

    before(async () => {
      alwaysSuccessfulTokens = [
        await waffle.deployMockContract(deployer, IERC20.abi),
        await waffle.deployMockContract(deployer, IERC20.abi),
      ];
      for (const token of alwaysSuccessfulTokens) {
        await token.mock.transfer.returns(true);
        await token.mock.transferFrom.returns(true);
      }
    });

    const emptySwap = () =>
      SwapEncoder.encodeSwap(
        testDomain,
        [],
        {
          sellToken: alwaysSuccessfulTokens[0].address,
          buyToken: alwaysSuccessfulTokens[1].address,
          sellAmount: ethers.constants.Zero,
          buyAmount: ethers.constants.Zero,
          validTo: 0,
          appData: 0,
          feeAmount: ethers.constants.Zero,
          kind: OrderKind.SELL,
          partiallyFillable: false,
        },
        traders[0],
        SigningScheme.EIP712,
      );

    it("rejects transactions from non-solvers", async () => {
      await expect(settlement.swap(...(await emptySwap()))).to.be.revertedWith(
        "GPv2: not a solver",
      );
    });

    it("executes swap and fee transfer with correct amounts", async () => {
      const order = {
        kind: OrderKind.BUY,
        receiver: traders[1].address,
        sellToken: fillBytes(20, 1),
        buyToken: fillBytes(20, 4),
        sellAmount: ethers.utils.parseEther("4.2"),
        buyAmount: ethers.utils.parseEther("13.37"),
        validTo: 0x01020304,
        appData: 0,
        feeAmount: ethers.utils.parseEther("1.0"),
        partiallyFillable: false,
        sellTokenBalance: OrderBalance.INTERNAL,
        buyTokenBalance: OrderBalance.ERC20,
      };

      const encoder = new SwapEncoder(testDomain);
      encoder.encodeSwapStep({
        poolId: fillBytes(32, 0xff),
        assetIn: fillBytes(20, 1),
        assetOut: fillBytes(20, 2),
        amount: ethers.utils.parseEther("42.0"),
      });
      encoder.encodeSwapStep({
        poolId: fillBytes(32, 0xfe),
        assetIn: fillBytes(20, 2),
        assetOut: fillBytes(20, 3),
        amount: ethers.utils.parseEther("1337.0"),
        userData: "0x010203",
      });
      encoder.encodeSwapStep({
        poolId: fillBytes(32, 0xfd),
        assetIn: fillBytes(20, 3),
        assetOut: fillBytes(20, 4),
        amount: ethers.utils.parseEther("6.0"),
      });
      await encoder.signEncodeTrade(order, traders[0], SigningScheme.EIP712);

      await vault.mock.batchSwap
        .withArgs(
          SwapKind.GIVEN_OUT,
          encoder.swaps,
          encoder.tokens,
          {
            sender: traders[0].address,
            fromInternalBalance: true,
            recipient: traders[1].address,
            toInternalBalance: false,
          },
          [order.sellAmount, 0, 0, order.buyAmount.mul(-1)],
          order.validTo,
        )
        .returns([order.sellAmount.div(2), 0, 0, order.buyAmount.mul(-1)]);
      await vault.mock.manageUserBalance
        .withArgs([
          {
            kind: UserBalanceOpKind.TRANSFER_INTERNAL,
            asset: order.sellToken,
            amount: order.feeAmount,
            sender: traders[0].address,
            recipient: settlement.address,
          },
        ])
        .returns();

      await authenticator.connect(owner).addSolver(solver.address);
      await expect(settlement.connect(solver).swap(...encoder.encodedSwap())).to
        .not.be.reverted;
    });

    describe("Balances", () => {
      const balanceVariants = [
        OrderBalance.ERC20,
        OrderBalance.EXTERNAL,
        OrderBalance.INTERNAL,
      ].flatMap((sellTokenBalance) =>
        [OrderBalance.ERC20, OrderBalance.INTERNAL].map((buyTokenBalance) => {
          return {
            name: `${sellTokenBalance} to ${buyTokenBalance}`,
            sellTokenBalance,
            buyTokenBalance,
          };
        }),
      );
      for (const { name, ...flags } of balanceVariants) {
        it(`performs an ${name} swap when specified`, async () => {
          const sellToken = await waffle.deployMockContract(
            deployer,
            IERC20.abi,
          );
          const buyToken = `0x${"cc".repeat(20)}`;
          const feeAmount = ethers.utils.parseEther("1.0");

          const encoder = new SwapEncoder(testDomain);
          await encoder.signEncodeTrade(
            {
              sellToken: sellToken.address,
              buyToken,
              receiver: traders[1].address,
              sellAmount: ethers.constants.Zero,
              buyAmount: ethers.constants.Zero,
              validTo: 0,
              appData: 0,
              feeAmount,
              kind: OrderKind.SELL,
              partiallyFillable: false,
              ...flags,
            },
            traders[0],
            SigningScheme.EIP712,
          );

          await vault.mock.batchSwap
            .withArgs(
              SwapKind.GIVEN_IN,
              [],
              encoder.tokens,
              {
                sender: traders[0].address,
                fromInternalBalance:
                  flags.sellTokenBalance == OrderBalance.INTERNAL,
                recipient: traders[1].address,
                toInternalBalance:
                  flags.buyTokenBalance == OrderBalance.INTERNAL,
              },
              [0, 0],
              0,
            )
            .returns([0, 0]);
          switch (flags.sellTokenBalance) {
            case OrderBalance.ERC20:
              await sellToken.mock.transferFrom
                .withArgs(traders[0].address, settlement.address, feeAmount)
                .returns(true);
              break;
            case OrderBalance.EXTERNAL:
              await vault.mock.manageUserBalance
                .withArgs([
                  {
                    kind: UserBalanceOpKind.TRANSFER_EXTERNAL,
                    asset: sellToken.address,
                    amount: feeAmount,
                    sender: traders[0].address,
                    recipient: settlement.address,
                  },
                ])
                .returns();
              break;
            case OrderBalance.INTERNAL:
              await vault.mock.manageUserBalance
                .withArgs([
                  {
                    kind: UserBalanceOpKind.TRANSFER_INTERNAL,
                    asset: sellToken.address,
                    amount: feeAmount,
                    sender: traders[0].address,
                    recipient: settlement.address,
                  },
                ])
                .returns();
              break;
          }

          await authenticator.connect(owner).addSolver(solver.address);
          await settlement.connect(solver).swap(...encoder.encodedSwap());
          await expect(
            settlement.connect(solver).swap(...encoder.encodedSwap()),
          ).to.not.be.reverted;
        });
      }
    });

    describe("Swap Variants", () => {
      const sellAmount = ethers.utils.parseEther("4.2");
      const buyAmount = ethers.utils.parseEther("13.37");

      for (const kind of [OrderKind.SELL, OrderKind.BUY]) {
        const order = {
          kind,
          sellToken: fillBytes(20, 1),
          buyToken: fillBytes(20, 2),
          sellAmount,
          buyAmount,
          validTo: 0x01020304,
          appData: 0,
          feeAmount: ethers.utils.parseEther("1.0"),
          sellTokenBalance: OrderBalance.INTERNAL,
          partiallyFillable: true,
        };
        const orderUid = () =>
          computeOrderUid(testDomain, order, traders[0].address);
        const encodeSwap = (swapExecution?: Partial<SwapExecution>) =>
          SwapEncoder.encodeSwap(
            testDomain,
            [],
            order,
            traders[0],
            SigningScheme.ETHSIGN,
            swapExecution,
          );

        it(`executes ${kind} order against swap`, async () => {
          const [swaps, tokens, trade] = await encodeSwap();

          await vault.mock.batchSwap.returns([sellAmount, buyAmount.mul(-1)]);
          await vault.mock.manageUserBalance.returns();

          await authenticator.connect(owner).addSolver(solver.address);
          await expect(settlement.connect(solver).swap(swaps, tokens, trade)).to
            .not.be.reverted;
        });

        it(`updates the filled amount to be the full ${kind} amount`, async () => {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const filledAmount = (order as any)[`${kind}Amount`];

          await vault.mock.batchSwap.returns([sellAmount, buyAmount.mul(-1)]);
          await vault.mock.manageUserBalance.returns();

          await authenticator.connect(owner).addSolver(solver.address);
          await settlement.connect(solver).swap(...(await encodeSwap()));

          expect(await settlement.filledAmount(orderUid())).to.equal(
            filledAmount,
          );
        });

        it(`reverts for cancelled ${kind} orders`, async () => {
          await vault.mock.batchSwap.returns([0, 0]);
          await vault.mock.manageUserBalance.returns();

          await settlement.connect(traders[0]).invalidateOrder(orderUid());
          await authenticator.connect(owner).addSolver(solver.address);
          await expect(
            settlement.connect(solver).swap(...(await encodeSwap())),
          ).to.be.revertedWith("order filled");
        });

        it(`reverts for partially filled ${kind} orders`, async () => {
          await vault.mock.batchSwap.returns([0, 0]);
          await vault.mock.manageUserBalance.returns();

          await settlement.setFilledAmount(orderUid(), 1);
          await authenticator.connect(owner).addSolver(solver.address);
          await expect(
            settlement.connect(solver).swap(...(await encodeSwap())),
          ).to.be.revertedWith("order filled");
        });

        it(`reverts when not exactly trading ${kind} amount`, async () => {
          await vault.mock.batchSwap.returns([
            sellAmount.sub(1),
            buyAmount.add(1).mul(-1),
          ]);
          await vault.mock.manageUserBalance.returns();

          await authenticator.connect(owner).addSolver(solver.address);
          await expect(
            settlement.connect(solver).swap(...(await encodeSwap())),
          ).to.be.revertedWith(`${kind} amount not respected`);
        });

        it(`reverts when specified limit amount does not satisfy ${kind} price`, async () => {
          const [swaps, tokens, trade] = await encodeSwap({
            // Specify a swap limit amount that is slightly worse than the
            // order's limit price.
            limitAmount:
              kind == OrderKind.SELL
                ? order.buyAmount.sub(1) // receive slightly less buy token
                : order.sellAmount.add(1), // pay slightly more sell token
          });

          await vault.mock.batchSwap.returns([sellAmount, buyAmount.mul(-1)]);
          await vault.mock.manageUserBalance.returns();

          await authenticator.connect(owner).addSolver(solver.address);
          await expect(
            settlement.connect(solver).swap(swaps, tokens, trade),
          ).to.be.revertedWith(
            kind == OrderKind.SELL ? "limit too low" : "limit too high",
          );
        });

        it(`emits a ${kind} trade event`, async () => {
          const [executedSellAmount, executedBuyAmount] =
            kind == OrderKind.SELL
              ? [order.sellAmount, order.buyAmount.mul(2)]
              : [order.sellAmount.div(2), order.buyAmount];
          await vault.mock.batchSwap.returns([
            executedSellAmount,
            executedBuyAmount.mul(-1),
          ]);
          await vault.mock.manageUserBalance.returns();

          await authenticator.connect(owner).addSolver(solver.address);
          await expect(settlement.connect(solver).swap(...(await encodeSwap())))
            .to.emit(settlement, "Trade")
            .withArgs(
              traders[0].address,
              order.sellToken,
              order.buyToken,
              executedSellAmount,
              executedBuyAmount,
              order.feeAmount,
              orderUid(),
            );
        });
      }
    });

    it("should emit a settlement event", async () => {
      await vault.mock.batchSwap.returns([0, 0]);
      await vault.mock.manageUserBalance.returns();

      await authenticator.connect(owner).addSolver(solver.address);
      await expect(settlement.connect(solver).swap(...(await emptySwap())))
        .to.emit(settlement, "Settlement")
        .withArgs(solver.address);
    });

    it("reverts on negative sell amounts", async () => {
      await vault.mock.batchSwap.returns([-1, 0]);
      await vault.mock.manageUserBalance.returns();

      await authenticator.connect(owner).addSolver(solver.address);
      await expect(
        settlement.connect(solver).swap(...(await emptySwap())),
      ).to.be.revertedWith("SafeCast: not positive");
    });

    it("reverts on positive buy amounts", async () => {
      await vault.mock.batchSwap.returns([0, 1]);
      await vault.mock.manageUserBalance.returns();

      await authenticator.connect(owner).addSolver(solver.address);
      await expect(
        settlement.connect(solver).swap(...(await emptySwap())),
      ).to.be.revertedWith("SafeCast: not positive");
    });

    it("reverts on unary negation overflow for buy amounts", async () => {
      const INT256_MIN = `-0x80${"00".repeat(31)}`;
      await vault.mock.batchSwap.returns([0, INT256_MIN]);
      await vault.mock.manageUserBalance.returns();

      await authenticator.connect(owner).addSolver(solver.address);
      await expect(
        settlement.connect(solver).swap(...(await emptySwap())),
      ).to.be.revertedWith("SafeCast: not positive");
    });
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
