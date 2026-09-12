// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IEvidenceRegistry.sol";
import "./interfaces/ICapabilityRegistry.sol";
import "./interfaces/IPolicyRegistry.sol";

/// @title AtlasUSC
/// @notice ATLAS integration with Creditcoin Universal Smart Contracts
/// @dev Accepts verified cross-chain facts and issues capabilities
contract AtlasUSC {
    event CrossChainFactStored(
        bytes32 indexed factId, address indexed sourceContract, bytes32 indexed eventSig, address subject, uint256 value
    );
    event CapabilityIssuedFromUSC(bytes32 indexed capabilityId, bytes32 indexed factId, address indexed subject);

    error Unauthorized();
    error InvalidQueryData();
    error CapabilityAlreadyIssued(bytes32 factId);

    IEvidenceRegistry public immutable evidenceRegistry;
    ICapabilityRegistry public immutable capabilityRegistry;
    IPolicyRegistry public immutable policyRegistry;

    mapping(bytes32 => bool) public factIssuedCapability;
    mapping(address => bool) public authorizedVerifiers;

    modifier onlyVerifier() {
        if (!authorizedVerifiers[msg.sender]) revert Unauthorized();
        _;
    }

    constructor(address evidenceRegistry_, address capabilityRegistry_, address policyRegistry_) {
        evidenceRegistry = IEvidenceRegistry(evidenceRegistry_);
        capabilityRegistry = ICapabilityRegistry(capabilityRegistry_);
        policyRegistry = IPolicyRegistry(policyRegistry_);
        authorizedVerifiers[msg.sender] = true;
    }

    /// @notice Set authorized USC worker/verifier
    function setVerifier(address verifier, bool authorized) external {
        authorizedVerifiers[verifier] = authorized;
    }

    /// @notice Process a verified cross-chain fact and issue capability
    function processUSCQuery(address sourceContract, bytes32 eventSig, address subject, uint256 value, bytes32 policyId)
        external
        onlyVerifier
        returns (bytes32 factId, bytes32 capabilityId)
    {
        factId = keccak256(abi.encodePacked(sourceContract, eventSig, subject, value, block.number));

        evidenceRegistry.recordEvidence(factId, sourceContract, eventSig, subject, value, block.number, bytes32(0));

        emit CrossChainFactStored(factId, sourceContract, eventSig, subject, value);

        if (!factIssuedCapability[factId]) {
            capabilityId = capabilityRegistry.createCapability(
                subject,
                eventSig,
                value,
                factId,
                policyId,
                policyRegistry.getPolicyTTL(policyId),
                keccak256("atlas:cross-chain-source"),
                sourceContract,
                keccak256(abi.encodePacked(eventSig, subject, value))
            );

            factIssuedCapability[factId] = true;

            emit CapabilityIssuedFromUSC(capabilityId, factId, subject);
        }
    }
}
