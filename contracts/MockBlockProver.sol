// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUSCProver.sol";

/// @title MockBlockProver
/// @notice Test double for the Creditcoin BlockProver precompile.
/// @dev In production, the real precompile verifies the Attestcoin proof over
///      the source transaction and returns its bytes; the IUSCProver adapter
///      then decodes the AuthorityUpdated event. Here the worker (`attest`) is
///      simulated for local Foundry runs. Swapping this out for the real
///      adapter does not change a single line of registry code.
contract MockBlockProver is IUSCProver {
    mapping(bytes32 => bool) public attested;
    mapping(bytes32 => ProvenAction) public attestedAction;

    event ProofAttested(
        bytes32 indexed sourceTxHash, address indexed sourceContract, uint256 indexed authorityId, uint64 version
    );

    /// @notice Simulate the proof worker recording a verified source tx.
    function attest(bytes32 sourceTxHash, ProvenAction calldata action) external {
        attested[sourceTxHash] = true;
        attestedAction[sourceTxHash] = action;
        emit ProofAttested(sourceTxHash, action.sourceContract, action.authorityId, action.version);
    }

    function verifyAndDecode(bytes32 sourceTxHash, bytes calldata proof)
        external
        returns (bool verified, ProvenAction memory action)
    {
        if (!attested[sourceTxHash]) return (false, attestedAction[sourceTxHash]);
        // A real proof is opaque bytes from the ProofBuilder; here we simply
        // require the caller to bind the proof to this tx hash so a raw tx hash
        // without a proof can never verify.
        if (proof.length == 0) return (false, attestedAction[sourceTxHash]);
        return (true, attestedAction[sourceTxHash]);
    }
}
