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
