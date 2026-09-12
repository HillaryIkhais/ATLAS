// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IUSCProver.sol";
import "./AbstractUSCProver.sol";

/// @title MockUSCProver
/// @notice Test double for RealUSCProver used when the BlockProver precompile is
///         not available (Foundry/anvil).
/// @dev Identical proof format and full ABI decode path: the ONLY thing skipped
///      is the cryptographic precompile call. This keeps forged-proof attack
///      tests honest about the decode surface while remaining runnable locally.
contract MockUSCProver is AbstractUSCProver, IUSCProver {
    error BlockZero();

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
        bytes memory,
        bytes32,
        BlockProverTypes.MerkleProofEntry[] memory,
        BlockProverTypes.ContinuityProof memory
    ) internal override returns (bool) {
        if (blockHeight == 0) revert BlockZero();
        return true;
    }
}