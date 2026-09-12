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

contract RunScenario is Script {
    address constant AGENT = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    bytes32 constant SOURCE_CHAIN = keccak256("ethereum_sepolia");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Addresses from deployment
        address evidenceRegistryAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
        address policyRegistryAddr = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
        address capabilityRegistryAddr = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
        address capabilityGuardAddr = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
        address creditMarketAddr = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
        address agentHistoryAddr = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707;

        EvidenceRegistry evidenceRegistry = EvidenceRegistry(evidenceRegistryAddr);
        PolicyRegistry policyRegistry = PolicyRegistry(policyRegistryAddr);
        CapabilityRegistry capabilityRegistry = CapabilityRegistry(capabilityRegistryAddr);
        MockCreditMarket creditMarket = MockCreditMarket(creditMarketAddr);
        AgentHistory agentHistory = AgentHistory(agentHistoryAddr);

        // === SCENARIO A: Happy path ===
        console.log("=== SCENARIO A: Happy Path ===");

        // 1. Record evidence (simulating verified repayments)
        evidenceRegistry.recordEvidence(
            keccak256("repayment-1"),
            agentHistoryAddr,
            keccak256("RepaymentRecorded"),
            AGENT,
            5000,
            block.number,
            keccak256("tx-1")
        );
        evidenceRegistry.recordEvidence(
            keccak256("repayment-2"),
            agentHistoryAddr,
            keccak256("RepaymentRecorded"),
            AGENT,
            8000,
            block.number,
            keccak256("tx-2")
        );
        evidenceRegistry.recordEvidence(
            keccak256("repayment-3"),
            agentHistoryAddr,
            keccak256("RepaymentRecorded"),
            AGENT,
            7000,
            block.number,
            keccak256("tx-3")
        );
        console.log("Evidence count:", evidenceRegistry.getEvidenceCount(AGENT));

        // 2. Create policy
        bytes32 policyId = keccak256("CREDIT_V1");
        policyRegistry.createPolicy(policyId, "Credit V1", 3, 20000, 16000, 25000, 600);
        console.log("Policy created, active:", policyRegistry.isPolicyActive(policyId));

        // 3. Create capability
        bytes32 evidenceRoot = keccak256("merkle-root-of-evidence");
        bytes32 capId = capabilityRegistry.createCapability(
            AGENT,
            keccak256("INCREASE_CREDIT"),
            25000,
            evidenceRoot,
            policyId,
            600,
            SOURCE_CHAIN,
            address(agentHistory),
            keccak256("repayments >= 3")
        );
        console.log("Capability created, valid:", capabilityRegistry.isCapabilityValid(capId));

        // 4. Execute via credit market
        creditMarket.increaseCredit(AGENT, 20000, capId);
        console.log("Credit limit:", creditMarket.getCreditLimit(AGENT));
        console.log("Remaining authority:", capabilityRegistry.getRemainingAuthority(capId));

        // === SCENARIO B: Over-authority ===
        console.log("\n=== SCENARIO B: Over-Authority ===");
        console.log("Agent requests $40K but capability is $25K");
        // This should fail if we try to consume more than allowed
        try creditMarket.increaseCredit(AGENT, 10000, capId) {
            console.log("ERROR: Should have reverted!");
        } catch {
            console.log("BLOCKED: Over-authority rejected");
        }

        // === SCENARIO C: Revocation ===
        console.log("\n=== SCENARIO C: State Deterioration ===");
        capabilityRegistry.revokeCapability(capId, "collateral dropped to 138%");
        console.log("Capability valid after revocation:", capabilityRegistry.isCapabilityValid(capId));

        try creditMarket.increaseCredit(AGENT, 5000, capId) {
            console.log("ERROR: Should have reverted!");
        } catch {
            console.log("BLOCKED: Revoked capability rejected");
        }

        vm.stopBroadcast();

        console.log("\n=== ALL SCENARIOS COMPLETE ===");
    }
}
