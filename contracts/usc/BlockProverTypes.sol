// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BlockProverTypes
/// @notice On-chain proof types used by ATLAS's Attestcoin/USC adapter.
/// @dev Mirrors the consumable proof shape produced by the gluwa usc-sdk's
///      proof generator: an inclusion proof (binary merkle over the attested
///      transaction) plus a continuity proof (consecutive block digests from
///      the Creditcoin attestation chain).
library BlockProverTypes {
    enum ProofKind {
        BinaryMerkle
    }

    struct MerkleProofEntry {
        bytes32 sibling;
        bool isLeft;
    }

    struct InclusionProof {
        ProofKind kind;
        bytes32 root;
        bytes data;
    }

    struct ContinuityProof {
        bytes32 lowerEndpointDigest;
        bytes32[] roots;
    }

    /// @dev ABI representation of one receipt log: `(address, bytes32[], bytes)`.
    struct ReceiptLog {
        address addr;
        bytes32[] topics;
        bytes data;
    }
}