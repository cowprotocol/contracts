import { expect } from "chai";
import { Contract, Wallet } from "ethers";
import { artifacts, ethers } from "hardhat";
import Proxy from "hardhat-deploy/extendedArtifacts/EIP173Proxy.json";

import {
  ContractName,
  DeploymentArguments,
  deterministicDeploymentAddress,
  implementationAddress,
  proxyInterface,
} from "../../src/ts";

import { deployTestContracts } from "./fixture";

async function contractAddress<C extends ContractName>(
  contractName: C,
  ...deploymentArguments: DeploymentArguments<C>
): Promise<string> {
  const artifact = await artifacts.readArtifact(contractName);
  return deterministicDeploymentAddress(artifact, deploymentArguments);
}

async function builtAndDeployedMetadataCoincide(
  contractAddress: string,
  contractName: string,
): Promise<boolean> {
  const contractArtifacts = await artifacts.readArtifact(contractName);

  const code = await ethers.provider.send("eth_getCode", [
    contractAddress,
    "latest",
  ]);

  // NOTE: The last 53 bytes in a deployed contract's bytecode contains the
  // contract metadata. Compare the deployed contract's metadata with the
  // compiled contract's metadata.
  // <https://docs.soliditylang.org/en/v0.7.6/metadata.html>
  const metadata = (bytecode: string) => bytecode.slice(-106);

  return metadata(code) === metadata(contractArtifacts.deployedBytecode);
}

describe("E2E: Deployment", () => {
  let owner: Wallet;
  let manager: Wallet;
  let user: Wallet;

  let authenticator: Contract;
  let vault: Contract;
  let settlement: Contract;
  let vaultRelayer: Contract;

  beforeEach(async () => {
    ({
      owner,
      manager,
      wallets: [user],
      authenticator,
      vault,
      settlement,
      vaultRelayer,
    } = await deployTestContracts());

    authenticator.connect(user);
    settlement.connect(user);
    vaultRelayer.connect(user);
  });

  describe("same built and deployed bytecode metadata", () => {
    it("authenticator", async () => {
      expect(
        await builtAndDeployedMetadataCoincide(
          await implementationAddress(ethers.provider, authenticator.address),
          "GPv2AllowListAuthentication",
        ),
      ).to.be.true;
    });

    it("settlement", async () => {
      expect(
        await builtAndDeployedMetadataCoincide(
          settlement.address,
          "GPv2Settlement",
        ),
      ).to.be.true;
    });

    it("vaultRelayer", async () => {
      expect(
        await builtAndDeployedMetadataCoincide(
          vaultRelayer.address,
          "GPv2VaultRelayer",
        ),
      ).to.be.true;
    });
  });

  describe("deterministic addresses", () => {
    describe("authenticator", () => {
      it("proxy", async () => {
        expect(
          deterministicDeploymentAddress(Proxy, [
            await implementationAddress(ethers.provider, authenticator.address),
            owner.address,
            authenticator.interface.encodeFunctionData("initializeManager", [
              manager.address,
            ]),
          ]),
        ).to.equal(authenticator.address);
      });

      it("implementation", async () => {
        expect(await contractAddress("GPv2AllowListAuthentication")).to.equal(
          await implementationAddress(ethers.provider, authenticator.address),
        );
      });
    });

    it("settlement", async () => {
      expect(
        await contractAddress(
          "GPv2Settlement",
          authenticator.address,
          vault.address,
        ),
      ).to.equal(settlement.address);
    });
  });

  describe("authorization", () => {
    it("authenticator has dedicated owner", async () => {
      const proxy = proxyInterface(authenticator);
      expect(await proxy.owner()).to.equal(owner.address);
    });

    it("authenticator has dedicated manager", async () => {
      expect(await authenticator.manager()).to.equal(manager.address);
    });
  });
});
