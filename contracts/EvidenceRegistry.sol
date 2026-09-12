// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IEvidenceRegistry.sol";

contract EvidenceRegistry is IEvidenceRegistry {
    mapping(bytes32 => Evidence) private _evidences;
    mapping(address => bytes32[]) private _subjectEvidenceIds;
    mapping(address => uint256) private _subjectEvidenceCount;

    modifier onlyValidEvidence(bytes32 evidenceId) {
        require(_evidences[evidenceId].valid, "EvidenceRegistry: evidence not valid");
        _;
    }

    function recordEvidence(
        bytes32 evidenceId,
        address sourceContract,
        bytes32 eventType,
        address subject,
        uint256 value,
        uint256 blockNumber,
        bytes32 txHash
    ) external {
        require(!_evidences[evidenceId].valid, "EvidenceRegistry: evidence already exists");
        require(subject != address(0), "EvidenceRegistry: invalid subject");
        require(sourceContract != address(0), "EvidenceRegistry: invalid source contract");

        _evidences[evidenceId] = Evidence({
            id: evidenceId,
            sourceContract: sourceContract,
            eventType: eventType,
            subject: subject,
            value: value,
            blockNumber: blockNumber,
            timestamp: block.timestamp,
            txHash: txHash,
            valid: true
        });

        _subjectEvidenceIds[subject].push(evidenceId);
        _subjectEvidenceCount[subject]++;

        emit EvidenceRecorded(evidenceId, subject, eventType, value);
    }

    function getEvidence(bytes32 evidenceId) external view returns (Evidence memory) {
        require(_evidences[evidenceId].valid, "EvidenceRegistry: evidence not found");
        return _evidences[evidenceId];
    }

    function getEvidenceCount(address subject) external view returns (uint256) {
        return _subjectEvidenceCount[subject];
    }

    function getSubjectEvidence(address subject, uint256 index) external view returns (bytes32) {
        require(index < _subjectEvidenceIds[subject].length, "EvidenceRegistry: index out of bounds");
        return _subjectEvidenceIds[subject][index];
    }

    function isValidEvidence(bytes32 evidenceId) external view returns (bool) {
        return _evidences[evidenceId].valid;
    }
}
