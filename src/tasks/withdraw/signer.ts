import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export type SignerOrAddress =
  | SignerWithAddress
  | { address: string; _isSigner: false };

export async function getSignerOrAddress(
  { ethers }: HardhatRuntimeEnvironment,
  origin?: string,
): Promise<SignerOrAddress> {
  const signers = await ethers.getSigners();
  const originAddress = ethers.utils.getAddress(origin ?? signers[0].address);
  return (
    signers.find(({ address }) => address === originAddress) ?? {
      address: originAddress,
      // Take advantage of the fact that all Ethers signers have `_isSigner` set
      // to `true`.
      _isSigner: false,
    }
  );
}

export function isSigner(solver: SignerOrAddress): solver is SignerWithAddress {
  return solver._isSigner;
}
