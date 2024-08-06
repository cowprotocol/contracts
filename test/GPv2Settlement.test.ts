import IERC20 from "@openzeppelin/contracts/build/contracts/IERC20.json";
import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { Contract } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import {
  OrderBalance,
  OrderKind,
  PRE_SIGNED,
  SigningScheme,
  SwapEncoder,
  SwapExecution,
  TypedDataDomain,
  computeOrderUid,
  domain,
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
