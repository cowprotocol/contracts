import IERC20 from "@openzeppelin/contracts/build/contracts/IERC20.json";
import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { BigNumberish, Contract } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import { BatchSwapStep } from "../src/ts";

import { SwapKind, UserBalanceOpKind } from "./balancer";
import { OrderBalanceId } from "./encoding";

describe("GPv2VaultRelayer", () => {
  const [deployer, creator, ...traders] = waffle.provider.getWallets();

  let vault: MockContract;
  let vaultRelayer: Contract;

  beforeEach(async () => {
    const IVault = await artifacts.readArtifact("IVault");
    vault = await waffle.deployMockContract(deployer, IVault.abi);

    const GPv2VaultRelayer = await ethers.getContractFactory(
      "GPv2VaultRelayer",
      creator,
    );
    vaultRelayer = await GPv2VaultRelayer.deploy(vault.address);
  });

  describe("batchSwapWithFee", () => {
    interface BatchSwapWithFee {
      kind: SwapKind;
      swaps: BatchSwapStep[];
      tokens: string[];
      funds: {
        sender: string;
        fromInternalBalance: boolean;
        recipient: string;
        toInternalBalance: boolean;
      };
      limits: BigNumberish[];
      deadline: number;
      feeTransfer: {
        account: string;
        token: string;
        amount: BigNumberish;
        balance: string;
      };
    }

    const encodeSwapParams = (p: Partial<BatchSwapWithFee>) => {
      return [
        p.kind ?? SwapKind.GIVEN_IN,
        p.swaps ?? [],
        p.tokens ?? [],
        p.funds ?? {
          sender: ethers.constants.AddressZero,
          fromInternalBalance: true,
          recipient: ethers.constants.AddressZero,
          toInternalBalance: true,
        },
        p.limits ?? [],
        p.deadline ?? 0,
        p.feeTransfer ?? {
          account: ethers.constants.AddressZero,
          token: ethers.constants.AddressZero,
          amount: ethers.constants.Zero,
          balance: OrderBalanceId.ERC20,
        },
      ];
    };

    describe("Fee Transfer", () => {
      it("should perform ERC20 transfer when not using direct ERC20 balance", async () => {
        const token = await waffle.deployMockContract(deployer, IERC20.abi);
        const amount = ethers.utils.parseEther("4.2");

        await vault.mock.batchSwap.returns([]);
        await token.mock.transferFrom
          .withArgs(traders[0].address, creator.address, amount)
          .returns(true);

        await expect(
          vaultRelayer.batchSwapWithFee(
            ...encodeSwapParams({
              feeTransfer: {
                account: traders[0].address,
                token: token.address,
                amount,
                balance: OrderBalanceId.ERC20,
              },
            }),
          ),
        ).to.not.be.reverted;
      });

      it("should perform Vault external balance transfer when specified", async () => {
        const token = await waffle.deployMockContract(deployer, IERC20.abi);
        const amount = ethers.utils.parseEther("4.2");

        await vault.mock.batchSwap.returns([]);
        await vault.mock.manageUserBalance
          .withArgs([
            {
              kind: UserBalanceOpKind.TRANSFER_EXTERNAL,
              asset: token.address,
              amount,
              sender: traders[0].address,
              recipient: creator.address,
            },
          ])
          .returns();

        await expect(
          vaultRelayer.batchSwapWithFee(
            ...encodeSwapParams({
              feeTransfer: {
                account: traders[0].address,
                token: token.address,
                amount,
                balance: OrderBalanceId.EXTERNAL,
              },
            }),
          ),
        ).to.not.be.reverted;
      });

      it("should perform Vault internal balance transfer when specified", async () => {
        const token = await waffle.deployMockContract(deployer, IERC20.abi);
        const amount = ethers.utils.parseEther("4.2");

        await vault.mock.batchSwap.returns([]);
        await vault.mock.manageUserBalance
          .withArgs([
            {
              kind: UserBalanceOpKind.TRANSFER_INTERNAL,
              asset: token.address,
              amount,
              sender: traders[0].address,
              recipient: creator.address,
            },
          ])
          .returns();

        await expect(
          vaultRelayer.batchSwapWithFee(
            ...encodeSwapParams({
              feeTransfer: {
                account: traders[0].address,
                token: token.address,
                amount,
                balance: OrderBalanceId.INTERNAL,
              },
            }),
          ),
        ).to.not.be.reverted;
      });

      it("should revert on failed ERC20 transfer", async () => {
        const token = await waffle.deployMockContract(deployer, IERC20.abi);
        const amount = ethers.utils.parseEther("4.2");

        await vault.mock.batchSwap.returns([]);
        await token.mock.transferFrom
          .withArgs(traders[0].address, creator.address, amount)
          .revertsWithReason("test error");

        await expect(
          vaultRelayer.batchSwapWithFee(
            ...encodeSwapParams({
              feeTransfer: {
                account: traders[0].address,
                token: token.address,
                amount,
                balance: OrderBalanceId.ERC20,
              },
            }),
          ),
        ).to.be.revertedWith("test error");
      });

      it("should revert on failed Vault external transfer", async () => {
        const token = await waffle.deployMockContract(deployer, IERC20.abi);
        const amount = ethers.utils.parseEther("4.2");

        await vault.mock.batchSwap.returns([]);
        await vault.mock.manageUserBalance
          .withArgs([
            {
              kind: UserBalanceOpKind.TRANSFER_EXTERNAL,
              asset: token.address,
              amount,
              sender: traders[0].address,
              recipient: creator.address,
            },
          ])
          .revertsWithReason("test error");

        await expect(
          vaultRelayer.batchSwapWithFee(
            ...encodeSwapParams({
              feeTransfer: {
                account: traders[0].address,
                token: token.address,
                amount,
                balance: OrderBalanceId.EXTERNAL,
              },
            }),
          ),
        ).to.be.revertedWith("test error");
      });

      it("should revert on failed Vault internal transfer", async () => {
        const token = await waffle.deployMockContract(deployer, IERC20.abi);
        const amount = ethers.utils.parseEther("4.2");

        await vault.mock.batchSwap.returns([]);
        await vault.mock.manageUserBalance
          .withArgs([
            {
              kind: UserBalanceOpKind.TRANSFER_INTERNAL,
              asset: token.address,
              amount,
              sender: traders[0].address,
              recipient: creator.address,
            },
          ])
          .revertsWithReason("test error");

        await expect(
          vaultRelayer.batchSwapWithFee(
            ...encodeSwapParams({
              feeTransfer: {
                account: traders[0].address,
                token: token.address,
                amount,
                balance: OrderBalanceId.INTERNAL,
              },
            }),
          ),
        ).to.be.revertedWith("test error");
      });
    });
  });
});
