// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPolicyRegistry {
    struct Policy {
        bytes32 id;
        string name;
        uint256 minRepayments;
        uint256 minRepaymentVolume;
        uint256 minCollateralRatioBps;
        uint256 maxCapability;
        uint64 capabilityTTL;
        uint64 version;
        bool active;
    }

    event PolicyCreated(bytes32 indexed policyId, string name, uint64 version);
    event PolicyUpdated(bytes32 indexed policyId, uint64 newVersion);

    function createPolicy(
        bytes32 policyId,
        string calldata name,
        uint256 minRepayments,
        uint256 minRepaymentVolume,
        uint256 minCollateralRatioBps,
        uint256 maxCapability,
        uint64 capabilityTTL
    ) external;

    function getPolicy(bytes32 policyId) external view returns (Policy memory);
    function isPolicyActive(bytes32 policyId) external view returns (bool);
    function getPolicyVersion(bytes32 policyId) external view returns (uint64);
    function getPolicyTTL(bytes32 policyId) external view returns (uint64);
}
