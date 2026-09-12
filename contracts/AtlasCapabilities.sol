// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AtlasAuthorityRegistry.sol";
import "./common/AuthorityTypes.sol";

/// @title AtlasCapabilities
/// @notice Issues state-bound capabilities on Creditcoin and enforces
///         non-widening delegation.
/// @dev A capability commits to a specific `authorityVersion`. The execution
///      guard (below) compares that version to the latest proven version in
///      the registry. If the source authorization has advanced, the capability
///      is superseded and cannot execute.
contract AtlasCapabilities {
    struct Capability {
        uint256 capabilityId;
        uint256 authorityId;
        address agent;
        bytes32 action;
        uint256 maxAmount;
        uint64 authorityVersion;
        uint256 expiresAt;
        bool revoked;
        uint256 parentId;
        uint256 consumedAmount;
    }

    mapping(uint256 => Capability) public capabilities;
    mapping(address => uint256[]) public agentCapabilities;
    mapping(uint256 => uint256[]) public delegatedCapabilities;
    uint256 public capabilityCount;

    AtlasAuthorityRegistry public immutable registry;

    // The execution guard is the sole authorized consumer.
    address public guard;

    event CapabilityIssued(
        uint256 indexed capId, address indexed agent, uint256 authorityId, uint64 authorityVersion, uint256 maxAmount
    );
    event CapabilityDelegated(
        uint256 indexed parentId, uint256 indexed childId, address childAgent, uint256 childMaxAmount
    );
    event CapabilityConsumed(uint256 indexed capId, uint256 amount, uint256 remaining);
    event CapabilityRevoked(uint256 indexed capId);

    error ZeroAmount();
    error ExceedsAuthority();
    error ExceedsExpiry();
    error AlreadyRevoked();
    error UnprovenAuthority();
    error AuthorityRevoked();
    error WrongAgent();
    error CannotDelegateNone();
    error Unauthorized();

    constructor(address _registry) {
        require(_registry != address(0));
        registry = AtlasAuthorityRegistry(_registry);
    }

    function setGuard(address _guard) external {
        require(_guard != address(0));
        guard = _guard;
    }

    // ──────────────────────────────────────────────────────────────────
    // Issuance
    // ──────────────────────────────────────────────────────────────────

    /// @notice Issue a capability bound to the currently proven authority version.
    function issueCapability(uint256 authorityId, address agent, bytes32 action, uint256 maxAmount, uint256 expiresAt)
        external
        returns (uint256 capId)
    {
        require(agent == msg.sender, "AtlasCapabilities: only self-issuance");
        require(maxAmount > 0, "AtlasCapabilities: zero amount");
        require(expiresAt > block.timestamp, "AtlasCapabilities: expired time");

        (uint64 version, uint256 authMax, uint256 authExp, AuthorityTypes.Status status, bytes32 authAction) =
            _loadProven(authorityId);
        if (status == AuthorityTypes.Status.REVOKED) revert AuthorityRevoked();
        if (action != authAction) revert ExceedsAuthority();
        if (maxAmount > authMax) revert ExceedsAuthority();
        if (expiresAt > authExp) revert ExceedsExpiry();

        capId = ++capabilityCount;
        capabilities[capId] = Capability({
            capabilityId: capId,
            authorityId: authorityId,
            agent: agent,
            action: action,
            maxAmount: maxAmount,
            authorityVersion: version,
            expiresAt: expiresAt,
            revoked: false,
            parentId: 0,
            consumedAmount: 0
        });

        agentCapabilities[agent].push(capId);
        emit CapabilityIssued(capId, agent, authorityId, version, maxAmount);
    }

    // ──────────────────────────────────────────────────────────────────
    // Delegation (non-widening)
    // ──────────────────────────────────────────────────────────────────

    /// @notice Delegate a capability to a sub-agent.  Authority can only narrow.
    function delegateCapability(uint256 parentId, address childAgent, uint256 childMaxAmount, uint256 childExpiry)
        external
        returns (uint256 childId)
    {
        Capability storage parent = capabilities[parentId];
        require(msg.sender == parent.agent, "AtlasCapabilities: wrong agent");
        require(!parent.revoked, "AtlasCapabilities: parent revoked");
        require(block.timestamp <= parent.expiresAt, "AtlasCapabilities: parent expired");
        require(childMaxAmount > 0, "AtlasCapabilities: zero amount");
        require(childExpiry > block.timestamp, "AtlasCapabilities: expired time");

        uint256 parentRemaining = parent.maxAmount - parent.consumedAmount;
        if (childMaxAmount > parentRemaining) revert ExceedsAuthority();
        if (childExpiry > parent.expiresAt) revert ExceedsExpiry();

        childId = ++capabilityCount;
        capabilities[childId] = Capability({
            capabilityId: childId,
            authorityId: parent.authorityId,
            agent: childAgent,
            action: parent.action,
            maxAmount: childMaxAmount,
            authorityVersion: parent.authorityVersion,
            expiresAt: childExpiry,
            revoked: false,
            parentId: parentId,
            consumedAmount: 0
        });

        // Reserve the parent's budget so delegation cannot exceed parent authority.
        parent.consumedAmount += childMaxAmount;

        delegatedCapabilities[parentId].push(childId);
        agentCapabilities[childAgent].push(childId);
        emit CapabilityDelegated(parentId, childId, childAgent, childMaxAmount);
    }

    // ──────────────────────────────────────────────────────────────────
    // Consumption (called only by the guard)
    // ──────────────────────────────────────────────────────────────────

    /// @notice Atomically consume capability budget (replay protection).
    function consume(uint256 capId, uint256 amount) external {
        require(msg.sender == guard, "AtlasCapabilities: only guard");
        require(amount > 0, "AtlasCapabilities: zero amount");
        Capability storage cap = capabilities[capId];
        require(cap.consumedAmount + amount <= cap.maxAmount, "AtlasCapabilities: exceeds budget");

        cap.consumedAmount += amount;
        emit CapabilityConsumed(capId, amount, cap.maxAmount - cap.consumedAmount);
    }

    // ──────────────────────────────────────────────────────────────────
    // Revocation
    // ──────────────────────────────────────────────────────────────────

    function revokeCapability(uint256 capId) external {
        Capability storage cap = capabilities[capId];
        if (msg.sender != cap.agent) revert WrongAgent();
        require(!cap.revoked, "AtlasCapabilities: already revoked");
        cap.revoked = true;
        emit CapabilityRevoked(capId);
    }

    // ──────────────────────────────────────────────────────────────────
    // View helpers
    // ──────────────────────────────────────────────────────────────────

    function getCapability(uint256 capId) external view returns (Capability memory) {
        return capabilities[capId];
    }

    function getDelegatedCapabilities(uint256 capId) external view returns (uint256[] memory) {
        return delegatedCapabilities[capId];
    }

    function _loadProven(uint256 authorityId)
        internal
        view
        returns (uint64 version, uint256 maxAmount, uint256 expiresAt, AuthorityTypes.Status status, bytes32 action)
    {
        AtlasAuthorityRegistry.ProvenAuthority memory pa = registry.getProvenAuthority(authorityId);
        require(pa.proven, "AtlasCapabilities: unproven authority");
        return (pa.version, pa.maxAmount, pa.expiresAt, pa.status, pa.action);
    }
}
