// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/ICapabilityRegistry.sol";
import "./interfaces/IPolicyRegistry.sol";
import "./interfaces/IStateOracle.sol";

/// @title CapabilityRegistry
/// @notice Issues, tracks, and revokes state-bound capabilities
/// @dev Capabilities are cryptographically tied to cross-chain state predicates
contract CapabilityRegistry is ICapabilityRegistry {
    IPolicyRegistry public immutable policyRegistry;
    IStateOracle public immutable stateOracle;

    mapping(bytes32 => Capability) private _capabilities;
    mapping(bytes32 => bytes32) private _parentCapabilities;
    mapping(address => bytes32[]) private _agentCapabilities;
    mapping(bytes32 => bytes32[]) private _delegatedCapabilities;
    mapping(bytes32 => bytes32) private _capabilityLineage;
    uint256 private _capabilityCount;

    modifier onlyActiveCapability(bytes32 capId) {
        require(_capabilities[capId].status == CapabilityStatus.ACTIVE, "CapabilityRegistry: not active");
        require(block.timestamp < _capabilities[capId].expiresAt, "CapabilityRegistry: expired");
        _;
    }

    modifier onlyCapabilityOwner(bytes32 capId, address subject) {
        require(_capabilities[capId].subject == subject, "CapabilityRegistry: not owner");
        _;
    }

    constructor(address _policyRegistry, address _stateOracle) {
        require(_policyRegistry != address(0), "CapabilityRegistry: zero policy");
        require(_stateOracle != address(0), "CapabilityRegistry: zero oracle");
        policyRegistry = IPolicyRegistry(_policyRegistry);
        stateOracle = IStateOracle(_stateOracle);
    }

    /// @notice Create a state-bound capability
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
    ) external returns (bytes32) {
        require(subject != address(0), "CapabilityRegistry: zero subject");
        require(maxAmount > 0, "CapabilityRegistry: zero amount");
        require(ttl > 0, "CapabilityRegistry: zero TTL");
        require(policyRegistry.isPolicyActive(policyId), "CapabilityRegistry: invalid policy");

        uint64 version = policyRegistry.getPolicyVersion(policyId);

        bytes32 capId = keccak256(
            abi.encodePacked(
                subject,
                action,
                evidenceRoot,
                policyId,
                version,
                block.timestamp,
                msg.sender,
                sourceChain,
                sourceContract,
                statePredicateHash
            )
        );

        require(_capabilities[capId].status == CapabilityStatus.NONE, "CapabilityRegistry: duplicate");

        _capabilities[capId] = Capability({
            id: capId,
            subject: subject,
            action: action,
            maxAmount: maxAmount,
            consumedAmount: 0,
            evidenceRoot: evidenceRoot,
            policyId: policyId,
            policyVersion: version,
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + ttl),
            nonce: uint256(capId),
            status: CapabilityStatus.ACTIVE,
            sourceChain: sourceChain,
            sourceContract: sourceContract,
            statePredicateHash: statePredicateHash,
            parentCapability: bytes32(0)
        });

        _agentCapabilities[subject].push(capId);
        _capabilityCount++;

        emit CapabilityCreated(capId, subject, action, maxAmount, uint64(block.timestamp + ttl));
        return capId;
    }

    /// @notice Delegate a capability to a sub-agent (non-widening)
    function delegateCapability(bytes32 parentCapId, address childSubject, uint256 childMaxAmount, uint64 childTTL)
        external
        onlyCapabilityOwner(parentCapId, msg.sender)
        returns (bytes32)
    {
        Capability storage parent = _capabilities[parentCapId];
        require(parent.status == CapabilityStatus.ACTIVE, "CapabilityRegistry: parent not active");
        require(block.timestamp < parent.expiresAt, "CapabilityRegistry: parent expired");

        // NON-WIDENING: child authority ≤ parent authority
        uint256 parentRemaining = parent.maxAmount - parent.consumedAmount;
        require(childMaxAmount > 0, "CapabilityRegistry: zero amount");
        require(childMaxAmount <= parentRemaining, "CapabilityRegistry: exceeds parent authority");

        // NON-WIDENING: child TTL ≤ parent TTL remaining
        require(childTTL > 0, "CapabilityRegistry: zero TTL");
        uint64 parentTTLRemaining = parent.expiresAt - uint64(block.timestamp);
        require(childTTL <= parentTTLRemaining, "CapabilityRegistry: exceeds parent TTL");

        bytes32 childCapId = keccak256(abi.encodePacked(parentCapId, childSubject, childMaxAmount, block.timestamp));

        _capabilities[childCapId] = Capability({
            id: childCapId,
            subject: childSubject,
            action: parent.action,
            maxAmount: childMaxAmount,
            consumedAmount: 0,
            evidenceRoot: parent.evidenceRoot,
            policyId: parent.policyId,
            policyVersion: parent.policyVersion,
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + childTTL),
            nonce: uint256(childCapId),
            status: CapabilityStatus.ACTIVE,
            sourceChain: parent.sourceChain,
            sourceContract: parent.sourceContract,
            statePredicateHash: parent.statePredicateHash,
            parentCapability: parentCapId
        });

        _parentCapabilities[childCapId] = parentCapId;
        _delegatedCapabilities[parentCapId].push(childCapId);
        _agentCapabilities[childSubject].push(childCapId);
        _capabilityCount++;

        emit CapabilityCreated(
            childCapId, childSubject, parent.action, childMaxAmount, uint64(block.timestamp + childTTL)
        );
        return childCapId;
    }

    /// @notice Consume capability with fresh state validation
    function consumeCapability(
        bytes32 capId,
        address subject,
        bytes32 action,
        uint256 amount,
        bytes32 freshEvidenceRoot
    ) external onlyActiveCapability(capId) {
        Capability storage cap = _capabilities[capId];

        require(cap.subject == subject, "CapabilityRegistry: wrong subject");
        require(cap.action == action, "CapabilityRegistry: wrong action");
        require(amount > 0, "CapabilityRegistry: zero amount");
        require(cap.consumedAmount + amount <= cap.maxAmount, "CapabilityRegistry: exceeds max");

        // FRESH PROOF: Validate state predicate at execution time
        // This solves the TOCTOU problem
        if (cap.sourceContract != address(0)) {
            bool stateValid = stateOracle.checkStatePredicate(
                cap.sourceChain, cap.sourceContract, subject, cap.statePredicateHash, freshEvidenceRoot
            );
            require(stateValid, "CapabilityRegistry: state predicate false");
        }

        cap.consumedAmount += amount;

        if (cap.consumedAmount == cap.maxAmount) {
            cap.status = CapabilityStatus.CONSUMED;
        }

        uint256 remaining = cap.maxAmount - cap.consumedAmount;
        emit CapabilityConsumed(capId, amount, remaining);
    }

    /// @notice Revoke a capability
    function revokeCapability(bytes32 capId, string calldata reason) external {
        require(_capabilities[capId].status == CapabilityStatus.ACTIVE, "CapabilityRegistry: not active");

        _capabilities[capId].status = CapabilityStatus.REVOKED;

        // Revoke all delegated capabilities
        bytes32[] storage delegated = _delegatedCapabilities[capId];
        for (uint256 i = 0; i < delegated.length; i++) {
            if (_capabilities[delegated[i]].status == CapabilityStatus.ACTIVE) {
                _capabilities[delegated[i]].status = CapabilityStatus.REVOKED;
                emit CapabilityRevoked(delegated[i], "parent revoked");
            }
        }

        emit CapabilityRevoked(capId, reason);
    }

    /// @notice Get capability details
    function getCapability(bytes32 capId) external view returns (Capability memory) {
        require(_capabilities[capId].status != CapabilityStatus.NONE, "CapabilityRegistry: not found");
        return _capabilities[capId];
    }

    /// @notice Check if capability is currently valid
    function isCapabilityValid(bytes32 capId) external view returns (bool) {
        Capability storage cap = _capabilities[capId];
        return cap.status == CapabilityStatus.ACTIVE && block.timestamp < cap.expiresAt;
    }

    /// @notice Get remaining authority
    function getRemainingAuthority(bytes32 capId) external view returns (uint256) {
        require(_capabilities[capId].status != CapabilityStatus.NONE, "CapabilityRegistry: not found");
        Capability storage cap = _capabilities[capId];
        if (cap.status != CapabilityStatus.ACTIVE || block.timestamp >= cap.expiresAt) {
            return 0;
        }
        return cap.maxAmount - cap.consumedAmount;
    }

    /// @notice Get capability count
    function getCapabilityCount() external view returns (uint256) {
        return _capabilityCount;
    }

    /// @notice Get all capabilities for an agent
    function getAgentCapabilities(address agent) external view returns (bytes32[] memory) {
        return _agentCapabilities[agent];
    }

    /// @notice Get delegated capabilities
    function getDelegatedCapabilities(bytes32 capId) external view returns (bytes32[] memory) {
        return _delegatedCapabilities[capId];
    }

    /// @notice Get parent capability
    function getParentCapability(bytes32 capId) external view returns (bytes32) {
        return _parentCapabilities[capId];
    }

    /// @notice Verify capability lineage
    function verifyLineage(bytes32 capId) external view returns (bool valid) {
        Capability storage cap = _capabilities[capId];
        if (cap.status == CapabilityStatus.NONE) return false;

        // Check parent chain
        bytes32 current = capId;
        while (_parentCapabilities[current] != bytes32(0)) {
            bytes32 parent = _parentCapabilities[current];
            Capability storage parentCap = _capabilities[parent];

            // Parent must be active (or revoked with this child)
            if (parentCap.status == CapabilityStatus.NONE) return false;

            // Child authority must not exceed parent
            if (_capabilities[current].maxAmount > parentCap.maxAmount) return false;

            // Child TTL must not exceed parent
            if (_capabilities[current].expiresAt > parentCap.expiresAt) return false;

            current = parent;
        }

        return true;
    }
}
