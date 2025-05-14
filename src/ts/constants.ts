/**
 * The EIP-712 type fields definition for a Gnosis Protocol v2 order.
 */
export const ORDER_TYPE_FIELDS = [
	{ name: "sellToken", type: "address" },
	{ name: "buyToken", type: "address" },
	{ name: "receiver", type: "address" },
	{ name: "sellAmount", type: "uint256" },
	{ name: "buyAmount", type: "uint256" },
	{ name: "validTo", type: "uint32" },
	{ name: "appData", type: "bytes32" },
	{ name: "feeAmount", type: "uint256" },
	{ name: "kind", type: "string" },
	{ name: "partiallyFillable", type: "bool" },
	{ name: "sellTokenBalance", type: "string" },
	{ name: "buyTokenBalance", type: "string" },
];
