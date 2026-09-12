// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/ICapabilityRegistry.sol";
import "./interfaces/IStateOracle.sol";

/// @title CapabilityGuard
/// @notice Validates execution requests with fresh state proofs
/// @dev The guard enforces that capability is valid AND state predicate is true at execution time
/// @dev This solves the TOCTOU problem: authority cannot outlive the state that justified it
contract CapabilityGuard {
    ICapabilityRegistry public immutable capabilityRegistry;
    IStateOracle public immutable stateOracle;

    event ExecutionValidated(bytes32 indexed capId, address indexed subject, bytes32 action, uint256 amount);
    event ExecutionBlocked(bytes32 indexed capId, address indexed subject, bytes32 action, string reason);

    constructor(address _capabilityRegistry, address _stateOracle) {
        require(_capabilityRegistry != address(0), "CapabilityGuard: zero address");
        require(_stateOracle != address(0), "CapabilityGuard: zero oracle");
        capabilityRegistry = ICapabilityRegistry(_capabilityRegistry);
        stateOracle = IStateOracle(_stateOracle);
    }

    /// @notice Validate a capability-based execution request
    /// @dev This is the atomic check that prevents TOCTOU attacks
    /// @dev Also validates that the state predicate is still satisfied at execution time
    function validateCapability(
        bytes32 capId,
        address subject,
        bytes32 action,
        uint256 amount,
        bytes32 freshEvidenceRoot
    ) external returns (bool) {
        try capabilityRegistry.getCapability(capId) returns (ICapabilityRegistry.Capability memory cap) {
            // Check 1: Capability must be active
            if (cap.status != ICapabilityRegistry.CapabilityStatus.ACTIVE) {
                emit ExecutionBlocked(capId, subject, action, "capability not active");
                return false;
            }

            // Check 2: Capability must not be expired (time-based)
            if (block.timestamp >= cap.expiresAt) {
                emit ExecutionBlocked(capId, subject, action, "capability expired");
                return false;
            }

            // Check 3: Subject must match
            if (cap.subject != subject) {
                emit ExecutionBlocked(capId, subject, action, "wrong subject");
                return false;
            }

            // Check 4: Action must match
            if (cap.action != action) {
                emit ExecutionBlocked(capId, subject, action, "wrong action");
                return false;
            }

            // Check 5: Amount must not exceed remaining
            uint256 remaining = cap.maxAmount - cap.consumedAmount;
            if (amount > remaining) {
                emit ExecutionBlocked(capId, subject, action, "exceeds authority");
                return false;
            }

            // Check 6: State predicate must still be satisfied (fresh proof)
            // This is the key innovation: authority is bound to current verified state
            bool stateValid = stateOracle.checkStatePredicate(
                cap.sourceChain, cap.sourceContract, subject, cap.statePredicateHash, freshEvidenceRoot
            );
            if (!stateValid) {
                emit ExecutionBlocked(capId, subject, action, "state predicate false");
                return false;
            }

            emit ExecutionValidated(capId, subject, action, amount);
            return true;
        } catch {
            emit ExecutionBlocked(capId, subject, action, "capability not found");
            return false;
        }
    }

    /// @notice Execute with capability - consumes and validates atomically
    /// @dev This is the atomic execution path that prevents TOCTOU
    function executeWithCapability(
        bytes32 capId,
        address subject,
        bytes32 action,
        uint256 amount,
        bytes32 freshEvidenceRoot
    ) external {
        // Validate first
        require(
            this.validateCapability(capId, subject, action, amount, freshEvidenceRoot),
            "CapabilityGuard: validation failed"
        );

        // Consume with fresh proof (atomic)
        capabilityRegistry.consumeCapability(capId, subject, action, amount, freshEvidenceRoot);
    }

    /// @notice Check lineage integrity before execution
    function checkLineage(bytes32 capId) external view returns (bool) {
        return capabilityRegistry.verifyLineage(capId);
    }
}
