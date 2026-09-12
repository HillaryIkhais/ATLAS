// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./common/AuthorityTypes.sol";

/// @title AtlasAuthorityController
/// @notice Source-chain authorization controller (deployed on Ethereum).
/// @dev Every mutation emits an `AuthorityUpdated` event carrying a strictly
///      monotonic `version`. That event is the cross-chain fact that
///      Attestcoin/USC proves and ATLAS consumes on Creditcoin. Versioning is
///      monotonic BY CONSTRUCTION at the source:
///          version(newState) > version(oldState)
///      No transition may ever decrease or repeat a version.
contract AtlasAuthorityController {
    mapping(uint256 => AuthorityTypes.AuthorityState) public authorities;
    mapping(uint256 => address) public authorizer;

    uint256 public authorityCount;
    uint64 internal constant ZERO_VERSION = 0;

    event AuthorityUpdated(
        uint256 indexed authorityId,
        address indexed agent,
        bytes32 indexed action,
        uint256 maxAmount,
        uint256 expiresAt,
        uint64 version,
        AuthorityTypes.Status status
    );

    error ZeroAgent();
    error ZeroAmount();
    error ExpiredTime();
    error Unauthorized();
    error NotActive();
    error NotNarrowing();
    error CannotRevokeNone();

    modifier onlyAuthorizer(uint256 authorityId) {
        if (msg.sender != authorizer[authorityId]) revert Unauthorized();
        _;
    }

    /// @notice Issue a new authority (ACTIVE, version 1).
    function createAuthority(address agent, bytes32 action, uint256 maxAmount, uint256 expiresAt)
        external
        returns (uint256 authorityId)
    {
        if (agent == address(0)) revert ZeroAgent();
        if (maxAmount == 0) revert ZeroAmount();
        if (expiresAt <= block.timestamp) revert ExpiredTime();

        authorityId = ++authorityCount;
        authorities[authorityId] = AuthorityTypes.AuthorityState({
            authorityId: authorityId,
            agent: agent,
            action: action,
            maxAmount: maxAmount,
            expiresAt: expiresAt,
            version: 1,
            status: AuthorityTypes.Status.ACTIVE
        });
        authorizer[authorityId] = msg.sender;

        emit AuthorityUpdated(authorityId, agent, action, maxAmount, expiresAt, 1, AuthorityTypes.Status.ACTIVE);
    }

    /// @notice Narrow an authority: version+1, maxAmount decreases.
    function narrowAuthority(uint256 authorityId, uint256 newMaxAmount) external onlyAuthorizer(authorityId) {
        AuthorityTypes.AuthorityState storage a = authorities[authorityId];
        _requireActiveish(a.status);
        if (newMaxAmount == 0) revert ZeroAmount();
        if (newMaxAmount >= a.maxAmount) revert NotNarrowing();

        uint64 next = a.version + 1;
        a.version = next;
        a.maxAmount = newMaxAmount;
        a.status = AuthorityTypes.Status.NARROWED;

        emit AuthorityUpdated(
            authorityId, a.agent, a.action, a.maxAmount, a.expiresAt, next, AuthorityTypes.Status.NARROWED
        );
    }

    /// @notice Revoke an authority: version+1, amount -> 0, status REVOKED.
    function revokeAuthority(uint256 authorityId) external onlyAuthorizer(authorityId) {
        AuthorityTypes.AuthorityState storage a = authorities[authorityId];
        _requireActiveish(a.status);

        uint64 next = a.version + 1;
        a.version = next;
        a.maxAmount = 0;
        a.status = AuthorityTypes.Status.REVOKED;

        emit AuthorityUpdated(authorityId, a.agent, a.action, 0, a.expiresAt, next, AuthorityTypes.Status.REVOKED);
    }

    function latestVersion(uint256 authorityId) external view returns (uint64) {
        return authorities[authorityId].version;
    }

    function getAuthority(uint256 authorityId) external view returns (AuthorityTypes.AuthorityState memory) {
        return authorities[authorityId];
    }

    function _requireActiveish(AuthorityTypes.Status status) internal pure {
        if (status != AuthorityTypes.Status.ACTIVE && status != AuthorityTypes.Status.NARROWED) revert NotActive();
    }
}
