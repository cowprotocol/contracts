import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { artifacts, ethers, waffle } from "hardhat";

import {
  EIP1271_MAGICVALUE,
  SettlementEncoder,
  SigningScheme,
  TypedDataDomain,
  computeOrderUid,
  domain,
  encodeEip1271SignatureData,
  hashOrder,
  signOrder,
} from "../src/ts";

import { encodeOrder } from "./encoding";
import { SAMPLE_ORDER } from "./testHelpers";

describe("GPv2Signing", () => {
  const [deployer, ...traders] = waffle.provider.getWallets();

  let signing: Contract;
  let testDomain: TypedDataDomain;

  beforeEach(async () => {
    const GPv2Signing = await ethers.getContractFactory(
      "GPv2SigningTestInterface",
    );

    signing = await GPv2Signing.deploy();

    const { chainId } = await ethers.provider.getNetwork();
    testDomain = domain(chainId, signing.address);
  });

  describe("recoverOrderFromTrade", () => {
    describe("uid uniqueness", () => {
      it("invalid EVM transaction encoding does not change order hash", async () => {
        // The variables for an EVM transaction are encoded in multiples of 32
        // bytes for all types except `string` and `bytes`. This extra padding
        // is usually filled with zeroes by the library that creates the
        // transaction. It can however be manually messed with, still producing
        // a valid transaction.
        // Computing GPv2's orderUid requires copying 32-byte-encoded addresses
        // from calldata to memory (buy and sell tokens), which are then hashed
        // together with the rest of the order. This copying procedure may keep
        // the padding bytes as they are in the (manipulated) calldata, since
        // Solidity does not make any guarantees on the padding bits of a
        // variable during execution. If these 12 padding bits were not zero
        // after copying, then the same order would end up with two different
        // uids. This test shows that this is not the case.

        const encoder = new SettlementEncoder(testDomain);
        await encoder.signEncodeTrade(
          SAMPLE_ORDER,
          traders[0],
          SigningScheme.EIP712,
        );

        const { uid: orderUid } = await signing.recoverOrderFromTradeTest(
          encoder.tokens,
          encoder.trades[0],
        );

        const encodedTransactionData = ethers.utils.arrayify(
          signing.interface.encodeFunctionData("recoverOrderFromTradeTest", [
            encoder.tokens,
            encoder.trades[0],
          ]),
        );

        // calldata encoding:
        //  -  4 bytes: signature
        //  - 32 bytes: pointer to first input value
        //  - 32 bytes: pointer to second input value
        //  - 32 bytes: first input value, array -> token array length
        //  - 32 bytes: first token address
        const encodedNumTokens = BigNumber.from(
          encodedTransactionData.slice(4 + 2 * 32, 4 + 3 * 32),
        );
        expect(encodedNumTokens).to.equal(2);
        const startTokenWord = 4 + 3 * 32;
        const encodedFirstToken = encodedTransactionData.slice(
          startTokenWord,
          startTokenWord + 32,
        );
        expect(encodedFirstToken.slice(0, 12).every((byte) => byte === 0)).to.be
          .true;
        expect(ethers.utils.hexlify(encodedFirstToken.slice(-20))).to.equal(
          encoder.tokens[0],
        );

        for (let i = startTokenWord; i < startTokenWord + 12; i++) {
          encodedTransactionData[i] = 42;
        }
        const encodedOutput = await ethers.provider.call({
          data: ethers.utils.hexlify(encodedTransactionData),
          to: signing.address,
        });
        expect(encodedOutput).to.contain(orderUid.slice(2));
      });
    });
  });

  describe("recoverOrderSigner", () => {
    it("should recover signing address for all supported ECDSA-based schemes", async () => {
      for (const scheme of [
        SigningScheme.EIP712,
        SigningScheme.ETHSIGN,
      ] as const) {
        const { data: signature } = await signOrder(
          testDomain,
          SAMPLE_ORDER,
          traders[0],
          scheme,
        );
        expect(
          await signing.recoverOrderSignerTest(
            encodeOrder(SAMPLE_ORDER),
            scheme,
            signature,
          ),
        ).to.equal(traders[0].address);
      }
    });

    it("should revert for invalid signing schemes", async () => {
      await expect(
        signing.recoverOrderSignerTest(encodeOrder(SAMPLE_ORDER), 42, "0x"),
      ).to.be.reverted;
    });

    it("should revert for malformed ECDSA signatures", async () => {
      for (const scheme of [SigningScheme.EIP712, SigningScheme.ETHSIGN]) {
        await expect(
          signing.recoverOrderSignerTest(
            encodeOrder(SAMPLE_ORDER),
            scheme,
            "0x",
          ),
        ).to.be.revertedWith("malformed ecdsa signature");
      }
    });

    it("should revert for invalid eip-712 order signatures", async () => {
      const { data: signature } = await signOrder(
        testDomain,
        SAMPLE_ORDER,
        traders[0],
        SigningScheme.EIP712,
      );

      // NOTE: `v` must be either `27` or `28`, so just set it to something else
      // to generate an invalid signature.
      const invalidSignature = ethers.utils.arrayify(
        ethers.utils.joinSignature(signature),
      );
      invalidSignature[64] = 42;

      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.EIP712,
          invalidSignature,
        ),
      ).to.be.revertedWith("invalid ecdsa signature");
    });

    it("should revert for invalid ethsign order signatures", async () => {
      const { data: signature } = await signOrder(
        testDomain,
        SAMPLE_ORDER,
        traders[0],
        SigningScheme.ETHSIGN,
      );

      // NOTE: `v` must be either `27` or `28`, so just set it to something else
      // to generate an invalid signature.
      const invalidSignature = ethers.utils.arrayify(
        ethers.utils.joinSignature(signature),
      );
      invalidSignature[64] = 42;

      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.ETHSIGN,
          invalidSignature,
        ),
      ).to.be.revertedWith("invalid ecdsa signature");
    });

    it("should verify EIP-1271 contract signatures by returning owner", async () => {
      const artifact = await artifacts.readArtifact("EIP1271Verifier");
      const verifier = await waffle.deployMockContract(deployer, artifact.abi);

      const message = hashOrder(testDomain, SAMPLE_ORDER);
      const eip1271Signature = "0x031337";
      await verifier.mock.isValidSignature
        .withArgs(message, eip1271Signature)
        .returns(EIP1271_MAGICVALUE);

      expect(
        await signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.EIP1271,
          encodeEip1271SignatureData({
            verifier: verifier.address,
            signature: eip1271Signature,
          }),
        ),
      ).to.equal(verifier.address);
    });

    it("should revert on an invalid EIP-1271 signature", async () => {
      const message = hashOrder(testDomain, SAMPLE_ORDER);
      const eip1271Signature = "0x031337";

      const artifact = await artifacts.readArtifact("EIP1271Verifier");
      const verifier1 = await waffle.deployMockContract(deployer, artifact.abi);

      await verifier1.mock.isValidSignature
        .withArgs(message, eip1271Signature)
        .returns("0xbaadc0d3");
      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.EIP1271,
          encodeEip1271SignatureData({
            verifier: verifier1.address,
            signature: eip1271Signature,
          }),
        ),
      ).to.be.revertedWith("invalid eip1271 signature");
    });

    it("should revert with non-standard EIP-1271 verifiers", async () => {
      const message = hashOrder(testDomain, SAMPLE_ORDER);
      const eip1271Signature = "0x031337";

      const NON_STANDARD_EIP1271_VERIFIER = [
        "function isValidSignature(bytes32 _hash, bytes memory _signature)",
      ]; // no return value
      const verifier = await waffle.deployMockContract(
        deployer,
        NON_STANDARD_EIP1271_VERIFIER,
      );

      await verifier.mock.isValidSignature
        .withArgs(message, eip1271Signature)
        .returns();
      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.EIP1271,
          encodeEip1271SignatureData({
            verifier: verifier.address,
            signature: eip1271Signature,
          }),
        ),
      ).to.be.reverted;
    });

    it("should revert for EIP-1271 signatures from externally owned accounts", async () => {
      // Transaction reverted: function call to a non-contract account
      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.EIP1271,
          encodeEip1271SignatureData({
            verifier: traders[0].address,
            signature: "0x00",
          }),
        ),
      ).to.be.reverted;
    });

    it("should revert if the EIP-1271 verification function changes the state", async () => {
      const StateChangingEIP1271 = await ethers.getContractFactory(
        "StateChangingEIP1271",
      );

      const evilVerifier = await StateChangingEIP1271.deploy();
      const message = hashOrder(testDomain, SAMPLE_ORDER);
      const eip1271Signature = "0x";

      expect(await evilVerifier.state()).to.equal(ethers.constants.Zero);
      await evilVerifier.isValidSignature(message, eip1271Signature);
      expect(await evilVerifier.state()).to.equal(ethers.constants.One);
      expect(
        await evilVerifier.callStatic.isValidSignature(
          message,
          eip1271Signature,
        ),
      ).to.equal(EIP1271_MAGICVALUE);

      // Transaction reverted and Hardhat couldn't infer the reason.
      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.EIP1271,
          encodeEip1271SignatureData({
            verifier: evilVerifier.address,
            signature: eip1271Signature,
          }),
        ),
      ).to.be.reverted;
      expect(await evilVerifier.state()).to.equal(ethers.constants.One);
    });

    it("should verify pre-signed order", async () => {
      const orderUid = computeOrderUid(
        testDomain,
        SAMPLE_ORDER,
        traders[0].address,
      );

      await signing.connect(traders[0]).setPreSignature(orderUid, true);
      expect(
        await signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.PRESIGN,
          traders[0].address,
        ),
      ).to.equal(traders[0].address);
    });

    it("should revert if order doesn't have pre-signature set", async () => {
      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.PRESIGN,
          traders[0].address,
        ),
      ).to.be.revertedWith("order not presigned");
    });

    it("should revert if pre-signed order is modified", async () => {
      await signing
        .connect(traders[0])
        .setPreSignature(
          computeOrderUid(testDomain, SAMPLE_ORDER, traders[0].address),
          true,
        );

      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder({
            ...SAMPLE_ORDER,
            buyAmount: ethers.constants.Zero,
          }),
          SigningScheme.PRESIGN,
          traders[0].address,
        ),
      ).to.be.revertedWith("order not presigned");
    });

    it("should revert for malformed pre-sign order UID", async () => {
      await expect(
        signing.recoverOrderSignerTest(
          encodeOrder(SAMPLE_ORDER),
          SigningScheme.PRESIGN,
          "0x",
        ),
      ).to.be.revertedWith("malformed presignature");
    });
  });
});
