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

contract ATLASTest is Test {
    EvidenceRegistry evidenceRegistry;
    PolicyRegistry policyRegistry;
    MinimalStateOracle stateOracle;
    CapabilityRegistry capabilityRegistry;
    CapabilityGuard capabilityGuard;
    MockCreditMarket creditMarket;
    AgentHistory agentHistory;

    address agent = makeAddr("agent");
    address attacker = makeAddr("attacker");

    bytes32 policyId = keccak256("CREDIT_V1");
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

        policyRegistry.createPolicy(
            policyId,
            "Credit V1",
            3, // min repayments
            20000, // min volume
            16000, // 160% collateral ratio
            25000, // max capability
            600 // TTL: 10 minutes
        );
    }

    // ========== EvidenceRegistry Tests ==========

    function test_EvidenceRecorded() public {
        bytes32 evidenceId = keccak256("evidence-1");
        evidenceRegistry.recordEvidence(
            evidenceId,
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            agent,
            5000,
            block.number,
            keccak256("tx-hash")
        );

        assertTrue(evidenceRegistry.isValidEvidence(evidenceId));
        assertEq(evidenceRegistry.getEvidenceCount(agent), 1);
    }

    function test_EvidenceDuplicateReverts() public {
        bytes32 evidenceId = keccak256("evidence-1");
        evidenceRegistry.recordEvidence(
            evidenceId,
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            agent,
            5000,
            block.number,
            keccak256("tx-hash")
        );

        vm.expectRevert("EvidenceRegistry: evidence already exists");
        evidenceRegistry.recordEvidence(
            evidenceId,
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            agent,
            5000,
            block.number,
            keccak256("tx-hash")
        );
    }

    function test_EvidenceInvalidSubjectReverts() public {
        bytes32 evidenceId = keccak256("evidence-1");
        vm.expectRevert("EvidenceRegistry: invalid subject");
        evidenceRegistry.recordEvidence(
            evidenceId,
            address(agentHistory),
            keccak256("RepaymentRecorded"),
            address(0),
            5000,
            block.number,
            keccak256("tx-hash")
        );
    }

    // ========== PolicyRegistry Tests ==========

    function test_PolicyCreated() public {
        assertTrue(policyRegistry.isPolicyActive(policyId));
        IPolicyRegistry.Policy memory p = policyRegistry.getPolicy(policyId);
        assertEq(p.minRepayments, 3);
        assertEq(p.minRepaymentVolume, 20000);
        assertEq(p.maxCapability, 25000);
        assertEq(p.capabilityTTL, 600);
        assertEq(p.version, 1);
    }

    function test_PolicyDuplicateReverts() public {
        vm.expectRevert("PolicyRegistry: policy already exists");
        policyRegistry.createPolicy(policyId, "Credit V1 Duplicate", 3, 20000, 16000, 25000, 600);
    }

    function test_PolicyNotFoundReverts() public {
        bytes32 fakePolicy = keccak256("FAKE");
        vm.expectRevert("PolicyRegistry: policy not found");
        policyRegistry.getPolicy(fakePolicy);
    }

    // ========== CapabilityRegistry Tests ==========

    function test_CapabilityCreated() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        ICapabilityRegistry.Capability memory cap = capabilityRegistry.getCapability(capId);
        assertEq(cap.subject, agent);
        assertEq(cap.action, action);
        assertEq(cap.maxAmount, 25000);
        assertEq(uint8(cap.status), uint8(ICapabilityRegistry.CapabilityStatus.ACTIVE));
        assertTrue(capabilityRegistry.isCapabilityValid(capId));
        assertEq(cap.sourceChain, sourceChain);
        assertEq(cap.sourceContract, address(agentHistory));
        assertEq(cap.statePredicateHash, keccak256("repayments >= 3"));
    }

    function test_CapabilityConsume() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.consumeCapability(capId, agent, action, 10000, bytes32(0));

        ICapabilityRegistry.Capability memory cap = capabilityRegistry.getCapability(capId);
        assertEq(cap.consumedAmount, 10000);
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 15000);
    }

    function test_CapabilityConsumeAll() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.consumeCapability(capId, agent, action, 25000, bytes32(0));

        ICapabilityRegistry.Capability memory cap = capabilityRegistry.getCapability(capId);
        assertEq(uint8(cap.status), uint8(ICapabilityRegistry.CapabilityStatus.CONSUMED));
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 0);
    }

    function test_CapabilityOverConsumeReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.expectRevert("CapabilityRegistry: exceeds max");
        capabilityRegistry.consumeCapability(capId, agent, action, 30000, bytes32(0));
    }

    function test_CapabilityWrongSubjectReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.expectRevert("CapabilityRegistry: wrong subject");
        capabilityRegistry.consumeCapability(capId, attacker, action, 10000, bytes32(0));
    }

    function test_CapabilityWrongActionReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        bytes32 wrongAction = keccak256("WRONG_ACTION");
        vm.expectRevert("CapabilityRegistry: wrong action");
        capabilityRegistry.consumeCapability(capId, agent, wrongAction, 10000, bytes32(0));
    }

    function test_CapabilityRevoke() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.revokeCapability(capId, "collateral deteriorated");

        assertFalse(capabilityRegistry.isCapabilityValid(capId));
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 0);
    }

    function test_CapabilityRevokedCannotConsume() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.revokeCapability(capId, "revoked");

        vm.expectRevert("CapabilityRegistry: not active");
        capabilityRegistry.consumeCapability(capId, agent, action, 10000, bytes32(0));
    }

    function test_CapabilityExpired() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.warp(block.timestamp + 601);

        assertFalse(capabilityRegistry.isCapabilityValid(capId));
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 0);

        vm.expectRevert("CapabilityRegistry: expired");
        capabilityRegistry.consumeCapability(capId, agent, action, 10000, bytes32(0));
    }

    // ========== CapabilityGuard Tests ==========

    function test_GuardValidExecution() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        assertTrue(capabilityGuard.validateCapability(capId, agent, action, 20000, bytes32(0)));

        creditMarket.increaseCredit(agent, 20000, capId);

        assertEq(creditMarket.getCreditLimit(agent), 20000);
    }

    function test_GuardOverLimitReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 40000, bytes32(0));
    }

    function test_GuardWrongSubjectReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, attacker, action, 10000, bytes32(0));
    }

    function test_GuardRevokedReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        capabilityRegistry.revokeCapability(capId, "revoked");

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 10000, bytes32(0));
    }

    function test_GuardExpiredReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        vm.warp(block.timestamp + 601);

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 10000, bytes32(0));
    }

    // ========== MockCreditMarket Tests ==========

    function test_CreditMarketIncrease() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        creditMarket.increaseCredit(agent, 20000, capId);
        assertEq(creditMarket.getCreditLimit(agent), 20000);
    }

    function test_CreditMarketReplayReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        creditMarket.increaseCredit(agent, 20000, capId);

        vm.expectRevert("CapabilityRegistry: exceeds max");
        creditMarket.increaseCredit(agent, 10000, capId);
    }

    // ========== Delegation Tests ==========

    function test_DelegationNonWidening() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 parentCapId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        address subAgent = makeAddr("subAgent");
        vm.prank(agent);
        bytes32 childCapId = capabilityRegistry.delegateCapability(
            parentCapId,
            subAgent,
            10000, // Less than parent
            300 // Less than parent TTL
        );

        ICapabilityRegistry.Capability memory child = capabilityRegistry.getCapability(childCapId);
        assertEq(child.subject, subAgent);
        assertEq(child.maxAmount, 10000);
        assertEq(child.parentCapability, parentCapId);
    }

    function test_DelegationExceedsParentReverts() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 parentCapId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
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

    function test_LineageVerification() public {
        bytes32 evidenceRoot = keccak256("evidence-root");
        bytes32 rootCapId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        address subAgent = makeAddr("subAgent");
        vm.prank(agent);
        bytes32 childCapId = capabilityRegistry.delegateCapability(rootCapId, subAgent, 10000, 300);

        assertTrue(capabilityRegistry.verifyLineage(childCapId));
    }

    // ========== Integration Test ==========

    function test_FullLifecycle() public {
        // 1. Record evidence
        bytes32 ev1 = keccak256("repayment-1");
        bytes32 ev2 = keccak256("repayment-2");
        bytes32 ev3 = keccak256("repayment-3");

        evidenceRegistry.recordEvidence(
            ev1, address(agentHistory), keccak256("Repayment"), agent, 5000, block.number, keccak256("tx1")
        );
        evidenceRegistry.recordEvidence(
            ev2, address(agentHistory), keccak256("Repayment"), agent, 8000, block.number, keccak256("tx2")
        );
        evidenceRegistry.recordEvidence(
            ev3, address(agentHistory), keccak256("Repayment"), agent, 7000, block.number, keccak256("tx3")
        );

        assertEq(evidenceRegistry.getEvidenceCount(agent), 3);

        // 2. Create capability based on evidence
        bytes32 evidenceRoot = keccak256("merkle-root-of-evidence");
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            25000,
            evidenceRoot,
            policyId,
            600,
            sourceChain,
            address(agentHistory),
            keccak256("repayments >= 3")
        );

        // 3. Execute via guard
        creditMarket.increaseCredit(agent, 20000, capId);
        assertEq(creditMarket.getCreditLimit(agent), 20000);

        // 4. Remaining authority
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 5000);

        // 5. Revocation prevents further execution
        capabilityRegistry.revokeCapability(capId, "collateral dropped");

        vm.expectRevert("CapabilityRegistry: not active");
        creditMarket.increaseCredit(agent, 5000, capId);
    }
}
