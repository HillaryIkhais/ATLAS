// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUSCProver.sol";

/// @title AtlasAuthorityRegistry
/// @notice On-Creditcoin proven authority store.
/// @dev Only the registered submitter may advance an authority. Every update
///      must carry a valid Attestcoin proof (verified by the prover adapter)
///      whose decoded `version` is STRICTLY GREATER than the current stored
///      version. This is the gate that makes supersession real: once v42 is
///      proven on Creditcoin, ATLAS can never again accept v41.
contract AtlasAuthorityRegistry {
    struct ProvenAuthority {
        uint64 version;
        uint256 maxAmount;
        uint256 expiresAt;
        AuthorityTypes.Status status;
        bytes32 sourceTxHash;
        uint256 sourceBlock;
        bytes32 action;
        address agent;
        bool proven;
    }

    mapping(uint256 => ProvenAuthority) public provenAuthorities;
    mapping(address => bool) public controllers; // trusted source controllers
    mapping(address => bool) public submitters; // proof submitters (workers)

    IUSCProver public immutable prover;
    uint256 public provenanceCount;

    event AuthorityProven(
        uint256 indexed authorityId,
        uint64 version,
        uint256 maxAmount,
        uint256 expiresAt,
        AuthorityTypes.Status status,
        bytes32 sourceTxHash
    );

    error UntrustedSource();
    error StaleVersion();
    error InvalidProof();
    error Unauthorized();

    constructor(address _prover) {
        require(_prover != address(0));
        prover = IUSCProver(_prover);
    }

    function setController(address c, bool ok) external {
        controllers[c] = ok;
    }

    function setSubmitter(address s, bool ok) external {
        submitters[s] = ok;
    }

    /// @notice Advance the on-chain proven authority for `authorityId`.
    function proveAuthorityUpdate(uint256 authorityId, bytes32 sourceTxHash, uint256 sourceBlock, bytes calldata proof)
        external
        returns (IUSCProver.ProvenAction memory)
    {
        if (!submitters[msg.sender]) revert Unauthorized();

        // 1. Verify Attestcoin proof + decode proven AuthorityUpdated.
        (bool verified, IUSCProver.ProvenAction memory action) = prover.verifyAndDecode(sourceTxHash, proof);
        if (!verified) revert InvalidProof();

        // 2. Proven tx must come from a registered source controller.
        if (!controllers[action.sourceContract]) revert UntrustedSource();

        // 3. Proven authority ID must match.
        if (action.authorityId != authorityId) revert StaleVersion();

        // 4. Version must be strictly newer than what we currently have.
        ProvenAuthority storage current = provenAuthorities[authorityId];
        if (action.version <= current.version) revert StaleVersion();

        // 5. Persist.
        current.version = action.version;
        current.maxAmount = action.maxAmount;
        current.expiresAt = action.expiresAt;
        current.status = action.status;
        current.sourceTxHash = sourceTxHash;
        current.sourceBlock = sourceBlock;
        current.action = action.action;
        current.agent = action.agent;
        current.proven = true;

        provenanceCount++;

        emit AuthorityProven(
            authorityId, action.version, action.maxAmount, action.expiresAt, action.status, sourceTxHash
        );
        return action;
    }

    function latestProvenVersion(uint256 authorityId) external view returns (uint64) {
        return provenAuthorities[authorityId].version;
    }

    function getProvenAuthority(uint256 authorityId) external view returns (ProvenAuthority memory) {
        return provenAuthorities[authorityId];
    }
}
