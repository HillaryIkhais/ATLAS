// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICapabilityRegistry {
    enum CapabilityStatus {
        NONE,
        ACTIVE,
        CONSUMED,
        EXPIRED,
        REVOKED
    }

    struct Capability {
        bytes32 id;
        address subject;
        bytes32 action;
        uint256 maxAmount;
        uint256 consumedAmount;
        bytes32 evidenceRoot;
        bytes32 policyId;
        uint64 policyVersion;
        uint64 issuedAt;
        uint64 expiresAt;
        uint256 nonce;
        CapabilityStatus status;
        bytes32 sourceChain;
        address sourceContract;
        bytes32 statePredicateHash;
        bytes32 parentCapability;
    }

    event CapabilityCreated(
        bytes32 indexed capId, address indexed subject, bytes32 action, uint256 maxAmount, uint64 expiresAt
    );
    event CapabilityConsumed(bytes32 indexed capId, uint256 amount, uint256 remaining);
    event CapabilityRevoked(bytes32 indexed capId, string reason);

    function createCapability(
        address subject,
        bytes32 action,
        uint256 maxAmount,
        bytes32 evidenceRoot,
        bytes32 policyId,
        uint64 ttl,
        bytes32 sourceChain,
        address sourceContract,
        bytes32 statePredicateHash
    ) external returns (bytes32);

    function delegateCapability(bytes32 parentCapId, address childSubject, uint256 childMaxAmount, uint64 childTTL)
        external
        returns (bytes32);

    function consumeCapability(
        bytes32 capId,
        address subject,
        bytes32 action,
        uint256 amount,
        bytes32 freshEvidenceRoot
    ) external;

    function revokeCapability(bytes32 capId, string calldata reason) external;
    function getCapability(bytes32 capId) external view returns (Capability memory);
    function isCapabilityValid(bytes32 capId) external view returns (bool);
    function getRemainingAuthority(bytes32 capId) external view returns (uint256);
    function getCapabilityCount() external view returns (uint256);
    function getAgentCapabilities(address agent) external view returns (bytes32[] memory);
    function getDelegatedCapabilities(bytes32 capId) external view returns (bytes32[] memory);
    function getParentCapability(bytes32 capId) external view returns (bytes32);
    function verifyLineage(bytes32 capId) external view returns (bool);
}
