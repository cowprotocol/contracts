import { expect } from "chai";
import { MockContract } from "ethereum-waffle";
import { Contract } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import { PRE_SIGNED, packOrderUidParams } from "../src/ts";

describe("GPv2Settlement", () => {
  const [deployer, owner, ...traders] = waffle.provider.getWallets();

  let authenticator: Contract;
  let vault: MockContract;
  let settlement: Contract;

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
