import { joinSignature } from "@ethersproject/bytes";
import { hashMessage } from "@ethersproject/hash";
import { SigningKey } from "@ethersproject/signing-key";
import { expect } from "chai";
import { ethers, waffle } from "hardhat";

import { SigningScheme, signOrder } from "../src/ts";

import { SAMPLE_ORDER } from "./testHelpers";

const patchedSignMessageBuilder =
  (key: SigningKey) =>
  async (message: string): Promise<string> => {
    // Reproducing `@ethersproject/wallet/src.ts/index.ts` sign message behavior
    const sig = joinSignature(key.signDigest(hashMessage(message)));

    // Unpack the signature
    const { r, s, v } = ethers.utils.splitSignature(sig);
    // Pack it again
    return ethers.utils.solidityPack(
      ["bytes32", "bytes32", "uint8"],
      // Remove last byte's `27` padding
      [r, s, v - 27],
    );
  };

describe("signOrder", () => {
  it("should pad the `v` byte when needed", async () => {
    const [signer] = waffle.provider.getWallets();
    // Patch signMessage
    signer.signMessage = patchedSignMessageBuilder(signer._signingKey());

    const domain = { name: "test" };

    for (const scheme of [
      SigningScheme.EIP712,
      SigningScheme.ETHSIGN,
    ] as const) {
      // Extract `v` from the signature data
      const v = ethers.utils.hexDataSlice(
        (await signOrder(domain, SAMPLE_ORDER, signer, scheme)).data as string,
        64,
        65,
      );
      // Confirm it is either 27 or 28, in hex
      expect(v).to.be.oneOf(["0x1b", "0x1c"]);
    }
  });
});
