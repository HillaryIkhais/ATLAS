// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title INativeQueryVerifier
/// @notice Interface of the Creditcoin BlockProver native precompile (`0xFD2`).
/// @dev The precompile verifies that `encodedTransaction` (ABI-encoded
///      tx+receipt via the gluwa usc-sdk `abiEncode`) is included in the block
///      attested on the source chain identified by `chainKey`, chained to the
///      CC3 attestation head via `continuityProof`. On success it emits an
///      internal event (hence `nonpayable`, not `view`).
interface INativeQueryVerifier {
    struct MerkleProofEntry {
        bytes32 hash;
        bool isLeft;
    }

    struct MerkleProof {
        bytes32 root;
        MerkleProofEntry[] siblings;
    }

    struct ContinuityProof {
        bytes32 lowerEndpointDigest;
        bytes32[] roots;
    }

    function verifyAndEmit(
        uint64 chainKey,
        uint64 height,
        bytes calldata encodedTransaction,
        MerkleProof calldata merkleProof,
        ContinuityProof calldata continuityProof
    ) external returns (bool);

    function calculateTxIndex(MerkleProof calldata merkleProof) external view returns (uint64);
}

/// @title NativeQueryVerifierLib
/// @notice Locates the BlockProver precompile at its well-known address.
library NativeQueryVerifierLib {
    address internal constant PRECOMPILE = 0x0000000000000000000000000000000000000FD2;

    function getVerifier() internal pure returns (INativeQueryVerifier) {
        return INativeQueryVerifier(PRECOMPILE);
    }

    /// @dev The precompile is wired into CC3-side EVM chains. It has no
    ///      runtime code on EVM networks that don't host the module, so probe
    ///      both the known chain ids and `code.length`.
    function hasPrecompile() internal view returns (bool) {
        uint256 chainId = block.chainid;
        if (chainId == 102030 || chainId == 102031 || chainId == 102033) {
            return true;
        }
        return PRECOMPILE.code.length > 0;
    }
}