// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPolicyRegistry.sol";

contract PolicyRegistry is IPolicyRegistry {
    mapping(bytes32 => Policy) private _policies;

    function createPolicy(
        bytes32 policyId,
        string calldata name,
        uint256 minRepayments,
        uint256 minRepaymentVolume,
        uint256 minCollateralRatioBps,
        uint256 maxCapability,
        uint64 capabilityTTL
    ) external {
        require(bytes(_policies[policyId].name).length == 0, "PolicyRegistry: policy already exists");
        require(minCollateralRatioBps > 0, "PolicyRegistry: invalid collateral ratio");
        require(maxCapability > 0, "PolicyRegistry: invalid max capability");
        require(capabilityTTL > 0, "PolicyRegistry: invalid TTL");

        _policies[policyId] = Policy({
            id: policyId,
            name: name,
            minRepayments: minRepayments,
            minRepaymentVolume: minRepaymentVolume,
            minCollateralRatioBps: minCollateralRatioBps,
            maxCapability: maxCapability,
            capabilityTTL: capabilityTTL,
            version: 1,
            active: true
        });

        emit PolicyCreated(policyId, name, 1);
    }

    function getPolicy(bytes32 policyId) external view returns (Policy memory) {
        require(bytes(_policies[policyId].name).length > 0, "PolicyRegistry: policy not found");
        return _policies[policyId];
    }

    function isPolicyActive(bytes32 policyId) external view returns (bool) {
        return _policies[policyId].active && bytes(_policies[policyId].name).length > 0;
    }

    function getPolicyVersion(bytes32 policyId) external view returns (uint64) {
        require(bytes(_policies[policyId].name).length > 0, "PolicyRegistry: policy not found");
        return _policies[policyId].version;
    }

    function getPolicyTTL(bytes32 policyId) external view returns (uint64) {
        require(bytes(_policies[policyId].name).length > 0, "PolicyRegistry: policy not found");
        return _policies[policyId].capabilityTTL;
    }
}
