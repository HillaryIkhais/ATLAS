// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AtlasAuthorityRegistry.sol";
import "./AtlasCapabilities.sol";
import "./AtlasLendingPool.sol";

/// @title AtlasExecutionGuard
/// @notice The atomic execution path on Creditcoin.
/// @dev Every protected action goes through this contract.  It validates
///      the capability, checks that the authority version is STILL THE LATEST
///      proven version, consumes authority atomically, and executes the state
///      transition.  This is the single point that closes the TOCTOU gap:
///      version check + state transition happen inside one transaction with
///      no window for interleaving state changes.
contract AtlasExecutionGuard {
    AtlasAuthorityRegistry public immutable registry;
    AtlasCapabilities public immutable capabilities;
    AtlasLendingPool public immutable lendingPool;

    event Executed(
        uint256 indexed capId, address indexed agent, bytes32 action, uint256 amount, uint64 authorityVersion
    );

    error NotAgent();
    error WrongAction();
    error Revoked();
    error Expired();
    error InsufficientCapability();
    error CapabilitySuperseded(uint64 capVersion, uint64 latestVersion);

    constructor(address _registry, address _capabilities, address _lendingPool) {
        require(_registry != address(0));
        require(_capabilities != address(0));
        require(_lendingPool != address(0));
        registry = AtlasAuthorityRegistry(_registry);
        capabilities = AtlasCapabilities(_capabilities);
        lendingPool = AtlasLendingPool(payable(_lendingPool));
    }

    /// @notice Execute a protected action atomically.
    function execute(uint256 capId, bytes32 action, uint256 amount) external {
        AtlasCapabilities.Capability memory cap = capabilities.getCapability(capId);

        // 1. Agent must be the capability holder.
        if (cap.agent != msg.sender) revert NotAgent();

        // 2. Action must match.
        if (cap.action != action) revert WrongAction();

        // 3. Capability must not be revoked.
        if (cap.revoked) revert Revoked();

        // 4. Capability must not be expired.
        if (block.timestamp > cap.expiresAt) revert Expired();

        // 5. Budget must cover the request.
        uint256 remaining = cap.maxAmount - cap.consumedAmount;
        if (amount == 0 || amount > remaining) revert InsufficientCapability();

        // 6. VERSION CHECK — the core invariant:
        //    capability.version MUST equal the latest proven version.
        uint64 latest = registry.latestProvenVersion(cap.authorityId);
        if (cap.authorityVersion != latest) revert CapabilitySuperseded(cap.authorityVersion, latest);

        // 7. Atomic consume + execute. If the lending pool reverts,
        //    the consume is rolled back too.
        capabilities.consume(capId, amount);
        lendingPool.borrow(msg.sender, amount, capId);

        emit Executed(capId, msg.sender, action, amount, latest);
    }

    /// @notice Can the agent still execute this capability right now?
    function canExecute(uint256 capId, bytes32 action, uint256 amount)
        external
        view
        returns (bool allowed, string memory reason, uint64 capVersion, uint64 latestVersion)
    {
        AtlasCapabilities.Capability memory cap = capabilities.getCapability(capId);
        latestVersion = registry.latestProvenVersion(cap.authorityId);
        capVersion = cap.authorityVersion;

        if (cap.revoked) return (false, "REVOKED", capVersion, latestVersion);
        if (block.timestamp > cap.expiresAt) return (false, "EXPIRED", capVersion, latestVersion);
        if (cap.agent != msg.sender) return (false, "NOT_AGENT", capVersion, latestVersion);
        if (cap.action != action) return (false, "WRONG_ACTION", capVersion, latestVersion);
        if (amount == 0 || amount > cap.maxAmount - cap.consumedAmount) {
            return (false, "INSUFFICIENT_CAP", capVersion, latestVersion);
        }
        if (cap.authorityVersion != latestVersion) {
            return (false, "CAPABILITY_SUPERSEDED", capVersion, latestVersion);
        }
        return (true, "", capVersion, latestVersion);
    }
}
