// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AuthorityTypes
/// @notice Shared authorization types used by both the source-chain
///         controller (Ethereum) and the Creditcoin-side registry.
/// @dev The `version` field is the load-bearing primitive: every mutation on
///      the source controller bumps it monotonically (v41 -> v42 -> v43),
///      which is what ATLAS proves across chains.
library AuthorityTypes {
    enum Status {
        NONE,
        ACTIVE,
        NARROWED,
        REVOKED
    }

    struct AuthorityState {
        uint256 authorityId;
        address agent;
        bytes32 action;
        uint256 maxAmount;
        uint256 expiresAt;
        uint64 version;
        Status status;
    }
}
