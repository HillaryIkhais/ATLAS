// pack-proof.js — Pack real Attestcoin proof into on-chain format
// Usage: node integration/pack-proof.js

const { ethers } = require("/Users/ikhaisoshuare/ATLAS/usc-builder-examples/node_modules/ethers");

const proofJson = require("./proof-v1-alt.json");

function packProofBytes(proof, blockHeight) {
    const coder = ethers.AbiCoder.defaultAbiCoder();

    // Build MerkleProofEntry[] for data encoding — must use tuple array format
    const siblings = proof.merkleProof.siblings;
    const data = coder.encode(
        ["bytes", "tuple(bytes32,bool)[]"],
        [proof.txBytes, siblings.map(s => [s.hash, s.isLeft])]
    );

    // InclusionProof: kind=0 (BinaryMerkle), root, data
    // ContinuityProof: lowerEndpointDigest, roots[]
    const proofBytes = coder.encode(
        ["uint64", "tuple(uint8 kind, bytes32 root, bytes data)", "tuple(bytes32 lowerEndpointDigest, bytes32[] roots)"],
        [
            blockHeight,
            [0, proof.merkleProof.root, data],
            [proof.continuityProof.lowerEndpointDigest, proof.continuityProof.roots]
        ]
    );
    return proofBytes;
}

const proof = proofJson;
const blockHeight = proof.headerNumber;
const proofBytes = packProofBytes(proof, blockHeight);

console.log("Block height:", blockHeight);
console.log("Proof bytes length:", proofBytes.length / 2 - 1, "bytes");
console.log("Proof bytes:", proofBytes);
