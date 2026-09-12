// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEvidenceRegistry {
    struct Evidence {
        bytes32 id;
        address sourceContract;
        bytes32 eventType;
        address subject;
        uint256 value;
        uint256 blockNumber;
        uint256 timestamp;
        bytes32 txHash;
        bool valid;
    }

    event EvidenceRecorded(bytes32 indexed evidenceId, address indexed subject, bytes32 eventType, uint256 value);

    function recordEvidence(
        bytes32 evidenceId,
        address sourceContract,
        bytes32 eventType,
        address subject,
        uint256 value,
        uint256 blockNumber,
        bytes32 txHash
    ) external;

    function getEvidence(bytes32 evidenceId) external view returns (Evidence memory);
    function getEvidenceCount(address subject) external view returns (uint256);
    function getSubjectEvidence(address subject, uint256 index) external view returns (bytes32);
    function isValidEvidence(bytes32 evidenceId) external view returns (bool);
}
