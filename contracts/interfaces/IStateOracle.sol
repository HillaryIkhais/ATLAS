// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IStateOracle
/// @notice Interface for on-chain state predicate verification
/// @dev Validates that current cross-chain state satisfies the predicate
///      that justified capability creation. Solves the TOCTOU problem.
interface IStateOracle {
    /// @notice Check if the state predicate is still satisfied
    /// @param sourceChain The source chain key (e.g., Ethereum chain ID)
    /// @param sourceContract The source contract address that generated the original event
    /// @param subject The agent/subject whose authority is being validated
    /// @param statePredicateHash The hash of the state predicate that justified capability creation
    /// @param freshEvidenceRoot Fresh USC evidence root from current block
    /// @return bool Whether the state predicate is satisfied given current state
    function checkStatePredicate(
        bytes32 sourceChain,
        address sourceContract,
        address subject,
        bytes32 statePredicateHash,
        bytes32 freshEvidenceRoot
    ) external view returns (bool);
}
