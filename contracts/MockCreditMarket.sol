// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/ICapabilityRegistry.sol";

/// @title MockCreditMarket
/// @notice Sample application demonstrating capability-gated execution
/// @dev Every state transition requires a valid capability
contract MockCreditMarket {
    ICapabilityRegistry public immutable capabilityRegistry;

    mapping(address => uint256) public creditLimits;
    mapping(address => bytes32[]) public executionHistory;

    event CreditIncreased(address indexed subject, uint256 amount, uint256 newLimit, bytes32 indexed capId);

    constructor(address _capabilityRegistry) {
        require(_capabilityRegistry != address(0), "MockCreditMarket: zero address");
        capabilityRegistry = ICapabilityRegistry(_capabilityRegistry);
    }

    /// @notice Increase credit limit - requires valid capability
    function increaseCredit(address subject, uint256 amount, bytes32 capId) external {
        // Atomic validation + consumption through CapabilityRegistry.
        // consumeCapability reverts on ANY failure (inactive, expired, wrong
        // subject/action, over-authority, stale state predicate), so no
        // credit-limit state transition can occur while the capability is
        // invalid. This is the same path CapabilityGuard enforces in production.
        capabilityRegistry.consumeCapability(
            capId,
            subject,
            keccak256("INCREASE_CREDIT"),
            amount,
            bytes32(0) // In production, fresh evidence root
        );

        // Execute state transition only after the capability is atomically consumed
        creditLimits[subject] += amount;
        executionHistory[subject].push(capId);

        emit CreditIncreased(subject, amount, creditLimits[subject], capId);
    }

    /// @notice Get current credit limit
    function getCreditLimit(address subject) external view returns (uint256) {
        return creditLimits[subject];
    }

    /// @notice Get execution history
    function getExecutionHistory(address subject) external view returns (bytes32[] memory) {
        return executionHistory[subject];
    }
}
