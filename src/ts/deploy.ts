import { utils } from "ethers";

/**
 * The salt used when deterministically deploying smart contracts.
 */
export const SALT = utils.formatBytes32String("Mattresses in Berlin!");

/**
 * Dictionary containing all deployed contract names.
 */
export const CONTRACT_NAMES = {
  authenticator: "GPv2AllowListAuthentication",
  settlement: "GPv2Settlement",
} as const;
