// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/EvidenceRegistry.sol";
import "../contracts/PolicyRegistry.sol";
import "../contracts/CapabilityRegistry.sol";
import "../contracts/CapabilityGuard.sol";
import "../contracts/MockCreditMarket.sol";
import "../contracts/AgentHistory.sol";
import "../contracts/MinimalStateOracle.sol";

contract DeployATLAS is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EvidenceRegistry evidenceRegistry = new EvidenceRegistry();
        console.log("EvidenceRegistry deployed at:", address(evidenceRegistry));

        PolicyRegistry policyRegistry = new PolicyRegistry();
        console.log("PolicyRegistry deployed at:", address(policyRegistry));

        MinimalStateOracle stateOracle = new MinimalStateOracle();
        console.log("MinimalStateOracle deployed at:", address(stateOracle));

        CapabilityRegistry capabilityRegistry = new CapabilityRegistry(address(policyRegistry), address(stateOracle));
        console.log("CapabilityRegistry deployed at:", address(capabilityRegistry));

        CapabilityGuard capabilityGuard = new CapabilityGuard(address(capabilityRegistry), address(stateOracle));
        console.log("CapabilityGuard deployed at:", address(capabilityGuard));

        MockCreditMarket creditMarket = new MockCreditMarket(address(capabilityRegistry));
        console.log("MockCreditMarket deployed at:", address(creditMarket));

        AgentHistory agentHistory = new AgentHistory();
        console.log("AgentHistory deployed at:", address(agentHistory));

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("EvidenceRegistry:", address(evidenceRegistry));
        console.log("PolicyRegistry:", address(policyRegistry));
        console.log("CapabilityRegistry:", address(capabilityRegistry));
        console.log("CapabilityGuard:", address(capabilityGuard));
        console.log("MockCreditMarket:", address(creditMarket));
        console.log("AgentHistory:", address(agentHistory));
    }
}
