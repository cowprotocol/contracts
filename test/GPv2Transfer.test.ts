import IERC20 from "@openzeppelin/contracts/build/contracts/IERC20.json";
import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { BigNumber, Contract } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import { BUY_ETH_ADDRESS } from "../src/ts";

import { UserBalanceOpKind } from "./balancer";
import { OrderBalanceId } from "./encoding";

describe("GPv2Transfer", () => {
  const [deployer, funder, ...traders] = waffle.provider.getWallets();

  let transfer: Contract;
  let vault: MockContract;
  let token: MockContract;

  beforeEach(async () => {
    const GPv2Transfer = await ethers.getContractFactory(
      "GPv2TransferTestInterface",
    );
    transfer = await GPv2Transfer.deploy();

    const IVault = await artifacts.readArtifact("IVault");
    vault = await waffle.deployMockContract(deployer, IVault.abi);
    token = await waffle.deployMockContract(deployer, IERC20.abi);
  });

  const amount = ethers.utils.parseEther("0.1337");

  describe("transferToAccounts", () => {
    it("should transfer external amount to account", async () => {
      await token.mock.transfer
        .withArgs(traders[0].address, amount)
        .returns(true);
      await expect(
        transfer.transferToAccountsTest(vault.address, [
          {
            account: traders[0].address,
            token: token.address,
            amount,
            balance: OrderBalanceId.ERC20,
          },
        ]),
      ).to.not.be.reverted;
    });

    it("should transfer internal amount to account", async () => {
      await vault.mock.manageUserBalance
        .withArgs([
          {
            kind: UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token.address,
            amount,
            sender: transfer.address,
            recipient: traders[0].address,
          },
        ])
        .returns();
      await expect(
        transfer.transferToAccountsTest(vault.address, [
          {
            account: traders[0].address,
            token: token.address,
            amount,
            balance: OrderBalanceId.INTERNAL,
          },
        ]),
      ).to.not.be.reverted;
    });

    it("should transfer Ether amount to account", async () => {
      await funder.sendTransaction({
        to: transfer.address,
        value: amount,
      });

      const initialBalance = await traders[0].getBalance();
      await transfer.transferToAccountsTest(vault.address, [
        {
          account: traders[0].address,
          token: BUY_ETH_ADDRESS,
          amount,
          balance: OrderBalanceId.ERC20,
        },
      ]);

      expect(await traders[0].getBalance()).to.deep.equal(
        initialBalance.add(amount),
      );
    });

    it("should transfer many external and internal amounts to recipient", async () => {
      // NOTE: Make sure we have enough traders for our test :)
      expect(traders).to.have.length.above(5);

      const externalTransfers = [];
      const internalTransfers = [];
      const ethTransfers = [];

      for (const [i, trader] of traders.entries()) {
        switch (i % 3) {
          case 0:
            externalTransfers.push({
              account: trader.address,
              token: token.address,
              amount,
              balance: OrderBalanceId.ERC20,
            });
            break;
          case 1:
            internalTransfers.push({
              account: trader.address,
              token: token.address,
              amount,
              balance: OrderBalanceId.INTERNAL,
            });
            break;
          case 2:
            ethTransfers.push({
              account: trader.address,
              token: BUY_ETH_ADDRESS,
              amount,
              balance: OrderBalanceId.ERC20,
            });
            break;
        }
      }

      for (const { account } of externalTransfers) {
        await token.mock.transfer.withArgs(account, amount).returns(true);
      }
      await vault.mock.manageUserBalance
        .withArgs(
          internalTransfers.map(({ account }) => ({
            kind: UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token.address,
            amount,
            sender: transfer.address,
            recipient: account,
          })),
        )
        .returns();
      const ethBalances: Record<string, BigNumber> = {};
      for (const { account } of ethTransfers) {
        ethBalances[account] = await ethers.provider.getBalance(account);
        await funder.sendTransaction({
          to: transfer.address,
          value: amount,
        });
      }

      await expect(
        transfer.transferToAccountsTest(vault.address, [
          ...externalTransfers,
          ...internalTransfers,
          ...ethTransfers,
        ]),
      ).to.not.be.reverted;

      for (const { account } of ethTransfers) {
        expect(await ethers.provider.getBalance(account)).to.equal(
          ethBalances[account].add(amount),
        );
      }
    });

    it("should revert on failed ERC20 transfers", async () => {
      await token.mock.transfer
        .withArgs(traders[0].address, amount)
        .revertsWithReason("test error");

      await expect(
        transfer.transferToAccountsTest(vault.address, [
          {
            account: traders[0].address,
            token: token.address,
            amount,
            balance: OrderBalanceId.ERC20,
          },
        ]),
      ).to.be.revertedWith("test error");
    });

    it("should revert on failed Vault deposit", async () => {
      await vault.mock.manageUserBalance
        .withArgs([
          {
            kind: UserBalanceOpKind.DEPOSIT_INTERNAL,
            asset: token.address,
            amount,
            sender: transfer.address,
            recipient: traders[0].address,
          },
        ])
        .revertsWithReason("test error");

      await expect(
        transfer.transferToAccountsTest(vault.address, [
          {
            account: traders[0].address,
            token: token.address,
            amount,
            balance: OrderBalanceId.INTERNAL,
          },
        ]),
      ).to.be.revertedWith("test error");
    });

    it("should revert when transfering Ether with internal balance", async () => {
      await expect(
        transfer.transferToAccountsTest(vault.address, [
          {
            account: traders[0].address,
            token: BUY_ETH_ADDRESS,
            amount,
            balance: OrderBalanceId.INTERNAL,
          },
        ]),
      ).to.be.revertedWith("unsupported internal ETH");
    });
  });
});
