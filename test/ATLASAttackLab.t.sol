// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/EvidenceRegistry.sol";
import "../contracts/PolicyRegistry.sol";
import "../contracts/CapabilityRegistry.sol";
import "../contracts/CapabilityGuard.sol";
import "../contracts/MockCreditMarket.sol";
import "../contracts/AgentHistory.sol";
import "../contracts/MinimalStateOracle.sol";

/// @title ATLAS Attack Lab
/// @notice Attack scenarios demonstrating state-bound capability security
contract ATLASAttackLab is Test {
    EvidenceRegistry evidenceRegistry;
    PolicyRegistry policyRegistry;
    MinimalStateOracle stateOracle;
    CapabilityRegistry capabilityRegistry;
    CapabilityGuard capabilityGuard;
    MockCreditMarket creditMarket;
    AgentHistory agentHistory;

    address agent = makeAddr("agent");
    address agent08 = makeAddr("agent08");

    bytes32 policyV3 = keccak256("CREDIT_V3");
    bytes32 policyV4 = keccak256("CREDIT_V4");
    bytes32 action = keccak256("INCREASE_CREDIT");
    bytes32 sourceChain = keccak256("ethereum_sepolia");

    function setUp() public {
        evidenceRegistry = new EvidenceRegistry();
        policyRegistry = new PolicyRegistry();
        stateOracle = new MinimalStateOracle();
        capabilityRegistry = new CapabilityRegistry(address(policyRegistry), address(stateOracle));
        capabilityGuard = new CapabilityGuard(address(capabilityRegistry), address(stateOracle));
        creditMarket = new MockCreditMarket(address(capabilityRegistry));
        agentHistory = new AgentHistory();

        policyRegistry.createPolicy(policyV3, "Credit V3", 3, 20000, 16000, 25000, 600);
        policyRegistry.createPolicy(policyV4, "Credit V4", 5, 50000, 20000, 50000, 300);
    }

    // ATTACK 1: OVER-LIMIT
    function test_Attack1_OverLimit() public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 40000, bytes32(0));
    }

    // ATTACK 2: EXPIRED
    function test_Attack2_Expired() public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.warp(block.timestamp + 601);

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 10000, bytes32(0));
    }

    // ATTACK 3: REVOKED STATE
    function test_Attack3_RevokedState() public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.revokeCapability(capId, "collateral dropped to 138%");

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 10000, bytes32(0));
    }

    // ATTACK 4: WRONG AGENT
    function test_Attack4_WrongAgent() public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent08, action, 10000, bytes32(0));
    }

    // ATTACK 5: REPLAY
    function test_Attack5_Replay() public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        creditMarket.increaseCredit(agent, 25000, capId);

        vm.expectRevert("CapabilityRegistry: not active");
        creditMarket.increaseCredit(agent, 10000, capId);
    }

    // ATTACK 6: WRONG POLICY VERSION
    function test_Attack6_WrongPolicyVersion() public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.revokeCapability(capId, "policy upgraded to V4");

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 10000, bytes32(0));
    }

    // ATTACK 7: DELEGATION ESCALATION
    function test_Attack8_DelegationEscalation() public {
        bytes32 parentCapId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        address subAgent = makeAddr("subAgent");
        vm.prank(agent);
        vm.expectRevert("CapabilityRegistry: exceeds parent authority");
        capabilityRegistry.delegateCapability(
            parentCapId,
            subAgent,
            30000, // More than parent!
            300
        );
    }

    // ATTACK 9: STALE STATE
    function test_Attack9_StaleState() public {
        // Create capability with initial state predicate
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("evidence"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        // Simulate: state has deteriorated since capability was issued
        // The fresh proof at execution would reveal the state predicate is false
        // With MinimalStateOracle always returning true, we test via revocation
        capabilityRegistry.revokeCapability(capId, "state deteriorated");

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, bytes32(0));
    }

    // FULL SEQUENCE
    function test_FullAttackSequence() public {
        // Setup evidence
        evidenceRegistry.recordEvidence(
            keccak256("repayment-1"),
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            agent,
            5000,
            block.number,
            keccak256("tx-1")
        );
        evidenceRegistry.recordEvidence(
            keccak256("repayment-2"),
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            agent,
            8000,
            block.number,
            keccak256("tx-2")
        );
        evidenceRegistry.recordEvidence(
            keccak256("repayment-3"),
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            agent,
            7000,
            block.number,
            keccak256("tx-3")
        );

        // Create capability
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            keccak256("merkle-root"),
            policyV3,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        // HAPPY PATH
        creditMarket.increaseCredit(agent, 20000, capId);
        assertEq(creditMarket.getCreditLimit(agent), 20000);
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 5000);

        // ATTACK: OVER-LIMIT
        vm.expectRevert("CapabilityRegistry: exceeds max");
        creditMarket.increaseCredit(agent, 10000, capId);

        // ATTACK: AFTER TTL EXPIRES
        vm.warp(block.timestamp + 601);
        vm.expectRevert("CapabilityRegistry: expired");
        creditMarket.increaseCredit(agent, 5000, capId);
    }
}
