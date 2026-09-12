// integration/index.ts — ATLAS USC integration script
// Run:  npx ts-node --esm integration/index.ts   (or use require in Node)
// Gate: Sepolia + CC3 funding. --mock flag builds proof bytes locally for Foundry tests.

require("dotenv").config();

const {
  proofGenerator,
  // BlockProverTypes types are used via SDK's proof shapes
} = require("@gluwa/usc-sdk");

const { ethers } = require("ethers");

/**
 * Pack proof bytes matching RealUSCProver._prove expectations:
 * proof = abi.encode(uint64 blockHeight, InclusionProof, ContinuityProof)
 * @param {object} proof - ContinuityResponse from SDK
 * @param {number} chainKey - source chain key (e.g. 1 for Sepolia)
 * @param {number} blockHeight - block number of the proven tx
 * @returns {string} hex-encoded packed proof bytes
 */
function packProofBytes(proof, chainKey, blockHeight) {
  const coder = ethers.AbiCoder.defaultAbiCoder();

  // Extract merkle siblings and root from proof.merkleProof
  const siblings = proof.merkleProof.siblings.map(s => ({
    sibling: s.hash,
    isLeft: s.isLeft
  }));

  // Build data = abi.encode(bytes txBytes, MerkleProofEntry[])
  // Solidity expects abi.decode(data, (bytes, MerkleProofEntry[])).
  // MerkleProofEntry = (bytes32 sibling, bool isLeft).
  // So data bytes = ABI encoding of (bytes, MerkleProofEntry[]) =
  //   first = txBytes as bytes, then for each sibling: its 32-byte sibling + bool isLeft.
  // In TS with AbiCoder, encode as:
  //   [txBytes (bytes), ...siblings flat: sibling1(32), isLeft1(0|1), sibling2(32), isLeft2(0|1), ...]
  const txBytes = proof.txBytes;
  const dataTypes = ["bytes"]; // start with bytes
  const dataValues = [txBytes]; // first element = txBytes

  for (const s of siblings) {
    dataTypes.push("bytes32", "bool");
    dataValues.push(s.sibling);  // already hex 0x + 32 bytes
    dataValues.push(s.isLeft ? 1 : 0);
  }

  const data = coder.encode(dataTypes, dataValues);

  // Build InclusionProof: kind=0 (BinaryMerkle), root, data
  const inclusionRoot = proof.merkleProof.root;
  const root32 = ethers.zeroPadValue(inclusionRoot, 32);

  // Build ContinuityProof: lowerEndpointDigest, roots[]
  const continuityLowerDigest = proof.continuityProof.lowerEndpointDigest;
  const continuityRoot32 = ethers.zeroPadValue(continuityLowerDigest, 32);
  const roots32 = proof.continuityProof.roots.map(r =>
    ethers.zeroPadValue(r, 32)
  );

  // Pack outer proof: abi.encode(uint64 blockHeight, uint8 kind, bytes32 root, bytes data, bytes32 lowerEndpointDigest, uint64 numRoots, bytes32[] roots)
  const outerTypes = [
    "uint64",
    "uint8",
    "bytes32",
    "bytes",
    "bytes32",
    "uint64",
    "bytes32[]"
  ];

  const outerValues = [
    BigInt(blockHeight),
    uint8(0), // kind = BinaryMerkle (ensure this is in scope; we'll cast)
    root32,
    data,
    continuityRoot32,
    BigInt(roots32.length),
    ...roots32
  ];

  const proofBytes = coder.encode(outerTypes, outerValues);
  return proofBytes; // hex string
}

/** Helper: ensure uint8(value) is in scope — we'll define a tiny factory. */
function uint8(v) {
  return { __type: "uint8", value: v }; // placeholder; actual encoding happens in coder.encode
}

/**
 * Build a fake ContinuityResponse for local Foundry testing (--mock flag).
 * The shape matches what RealUSCProver._prove expects after packProofBytes.
 */
function buildFakeProof() {
  return {
    chainKey: 1,
    headerNumber: 1,
    txIndex: 0,
    txHash: "0x" + "a".repeat(64),
    txBytes: "0x" + "a".repeat(130),
    merkleProof: {
      root: "0x" + "a".repeat(64),
      siblings: [{ hash: "0x" + "a".repeat(64), isLeft: true }]
    },
    continuityProof: {
      lowerEndpointDigest: "0x" + "a".repeat(64),
      roots: ["0x" + "a".repeat(64)]
    },
    cached: false,
    generatedAt: new Date()
  };
}

async function main() {
  const isMock = process.argv.includes("--mock");

  const sepoliaRpc = process.env.SEPOLIA_RPC_URL;
  const deployerPk = process.env.DEPLOYER_PRIVATE_KEY;
  const proofBuilderUrl = process.env.PROOF_BUILDER_URL ?? "https://prover.cc3-testnet.creditcoin.network";
  const sourceChainKey = Number(process.env.SOURCE_CHAIN_KEY ?? "1");

  if (!sepoliaRpc || !deployerPk) {
    console.error("Missing required env vars: SEPOLIA_RPC_URL, DEPLOYER_PRIVATE_KEY");
    process.exit(1);
  }

  if (isMock) {
    console.log("=== Mock mode: building proof bytes from fabricated data ===");
    const fakeProof = buildFakeProof();
    const proofBytes = packProofBytes(fakeProof, sourceChainKey, 1);
    console.log("Packed proof bytes (hex):", proofBytes);
    console.log(
      "These bytes can be passed to registry.proveAuthorityUpdate(authorityId, txHash, blockHeight, proofBytes) in Foundry"
    );
    console.log("\nRun: forge test --fork-url <sepolia-rpc> to verify decode path");
    return;
  }

  // Real mode: generate proof via SDK
  if (!process.env.CREDITCOIN_RPC_URL) {
    console.error("CREDITCOIN_RPC_URL required for real mode");
    process.exit(1);
  }

  console.log("=== Real mode: generating proof via SDK ===");
  const provider = new ethers.providers.JsonRpcProvider(sepoliaRpc);
  const deployer = new ethers.Wallet(deployerPk, provider);

  const apiProvider = new proofGenerator.api.ProverAPIProofGenerator(
    sourceChainKey,
    proofBuilderUrl
  );

  const txHash = process.env.SOURCE_CHAIN_TXN_HASH;
  if (!txHash) {
    console.error("Set SOURCE_CHAIN_TXN_HASH env var with a Sepolia tx hash the prover can index.");
    process.exit(1);
  }

  console.log(`Fetching proof for tx hash: ${txHash}`);
  const proofResult = await apiProvider.generateProof(txHash);

  if (!proofResult.success) {
    console.error("Proof generation failed:", proofResult.error);
    process.exit(1);
  }

  const continuityResponse = proofResult.data;
  console.log("Proof generated successfully");

  const blockHeight = Number(continuityResponse.headerNumber);
  const proofBytes = packProofBytes(continuityResponse, sourceChainKey, blockHeight);
  console.log("Packed proof bytes (hex,", proofBytes.length, "bytes):", proofBytes);

  console.log("\n--- Integration gate ---");
  console.log(
    "When Sepolia+CC3 funding is available, submit via Foundry:",
    `\n  registry.proveAuthorityUpdate(authorityId, "${txHash}", ${blockHeight}, "${proofBytes}")`
  );
  console.log("Ensure submitter is whitelisted in AtlasAuthorityRegistry.");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});