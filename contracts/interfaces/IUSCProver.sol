// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../common/AuthorityTypes.sol";

/// @title IUSCProver
/// @notice Adapter for Attestcoin/USC proof verification on Creditcoin.
/// @dev Production implementation wraps the Creditcoin BlockProver precompile:
///      given an Attestcoin proof it verifies the source transaction's block
///      inclusion AND decodes the proven transaction so the caller can extract
///      the original `AuthorityUpdated` event. For local testing, MockBlockProver
///      stands in; the interface is identical so swapping is one line.
interface IUSCProver {
    /// @dev The decoded cross-chain fact proven by an Attestcoin proof.
    struct ProvenAction {
        address sourceContract;
        uint256 authorityId;
        address agent;
        bytes32 action;
        uint256 maxAmount;
        uint256 expiresAt;
        uint64 version;
        AuthorityTypes.Status status;
    }

    /// @notice Verify an Attestcoin proof and decode the source transaction data.
    /// @param sourceTxHash The source-chain transaction hash being proven.
    /// @param proof The Attestcoin/USC proof (opaque bytes).
    /// @return verified True only if the proof is cryptographically valid.
    /// @return action The decoded AuthorityUpdated payload from the proven tx.
    /// @dev Intentionally `nonpayable`, not `view`: the production prover must
    ///      call the CC3 BlockProver precompile's `verifyAndEmit`, which emits a
    ///      verification event. Solidity requires overrides to keep identical
    ///      mutability, so the whole interface is nonpayable.
    function verifyAndDecode(bytes32 sourceTxHash, bytes calldata proof)
        external
        returns (bool verified, ProvenAction memory action);
}
