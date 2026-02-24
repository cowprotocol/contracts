import { promises as fs } from "fs";
import path from "path";

import glob from "glob";
import globby from "globby";
import {
  TASK_COMPILE_SOLIDITY_EMIT_ARTIFACTS,
  TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS,
} from "hardhat/builtin-tasks/task-names";
import { subtask } from "hardhat/config";

const projectRoot = path.join(__dirname, "../..");
const artifactsRoot = path.join(projectRoot, "build/artifacts/src/contracts");
const exportedArtifactsRoot = path.join(projectRoot, "lib/contracts");

const additionalSourcesDir = path.join(projectRoot, "solc_0.7", "**", "*.sol");

async function copyArtifacts(): Promise<void> {
  const artifacts = await globby(["**/*.json", "!**/*.dbg.json", "!test/"], {
    cwd: artifactsRoot,
  });

  await fs.mkdir(exportedArtifactsRoot, { recursive: true });
  for (const artifact of artifacts) {
    const { base } = path.parse(artifact);

    const artifactPath = path.join(artifactsRoot, artifact);
    const exportedArtifactPath = path.join(exportedArtifactsRoot, base);
    await fs.copyFile(artifactPath, exportedArtifactPath);
  }
}

export function setupArtifactsTasks(): void {
  subtask(TASK_COMPILE_SOLIDITY_EMIT_ARTIFACTS).setAction(
    async (_args, _hre, runSuper) => {
      const result = await runSuper();
      await copyArtifacts();
      return result;
    },
  );

  // This is a tiny override task to add another compilation directory `solc_0.7`
  // This is needed for Cannon compilation/verification
  subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
    async (_, hre, runSuper) => {
      const paths = await runSuper();

      const otherPaths = glob.sync(additionalSourcesDir);

      return [...paths, ...otherPaths];
    },
  );
}
