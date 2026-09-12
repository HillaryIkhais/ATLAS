// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IUSCProver.sol";
import "./AbstractUSCProver.sol";
import "./INativeQueryVerifier.sol";

/// @title RealUSCProver
/// @notice Production IUSCProver adapter that verifies Attestcoin/USC proofs
///         through the Creditcoin BlockProver native precompile (0xFD2).
/// @dev Deploy ONLY on a Creditcoin-side EVM chain that hosts the precompile
///      (CC3 devnet/testnet/mainnet, or a localnode where the module is wired).
///      `sourceChainKey` pins the accepted source chain and `authorizedController`
///      pins the source contract the proven `AuthorityUpdated` events must come
///      from. `verifyAndDecode` is intentionally `nonpayable` (the precompile
///      emits an event), which Solidity permits as a loosening of the interface's
///      `view` declaration.
contract RealUSCProver is AbstractUSCProver, IUSCProver {
    error PrecompileUnavailable();

    constructor(uint64 _sourceChainKey, address _authorizedController)
        AbstractUSCProver(_sourceChainKey, _authorizedController)
    {}

    function verifyAndDecode(bytes32, bytes calldata proof)
        external
        override(IUSCProver)
        returns (bool verified, IUSCProver.ProvenAction memory action)
    {
        return _prove(proof);
    }

    function _verifyNativeCall(
        uint64 blockHeight,
        bytes memory txBytes,
        bytes32 root,
        BlockProverTypes.MerkleProofEntry[] memory siblings,
        BlockProverTypes.ContinuityProof memory continuityProof
    ) internal override returns (bool) {
        if (!NativeQueryVerifierLib.hasPrecompile()) revert PrecompileUnavailable();

        INativeQueryVerifier.MerkleProofEntry[] memory nativeSiblings =
            new INativeQueryVerifier.MerkleProofEntry[](siblings.length);
        for (uint256 i = 0; i < siblings.length; i++) {
            nativeSiblings[i] = INativeQueryVerifier.MerkleProofEntry({
                hash: siblings[i].sibling,
                isLeft: siblings[i].isLeft
            });
        }

        return NativeQueryVerifierLib.getVerifier().verifyAndEmit(
            sourceChainKey,
            blockHeight,
            txBytes,
            INativeQueryVerifier.MerkleProof({root: root, siblings: nativeSiblings}),
            INativeQueryVerifier.ContinuityProof({
                lowerEndpointDigest: continuityProof.lowerEndpointDigest,
                roots: continuityProof.roots
            })
        );
    }
}