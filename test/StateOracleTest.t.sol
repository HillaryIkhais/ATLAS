// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/EvidenceRegistry.sol";
import "../contracts/PolicyRegistry.sol";
import "../contracts/CapabilityRegistry.sol";
import "../contracts/CapabilityGuard.sol";
import "../contracts/StateOracle.sol";
import "../contracts/AgentHistory.sol";

/// @title StateOracleTest
/// @notice Proves the ATLAS core invariant:
///         EXECUTE => CURRENT_VERIFIED_STATE |= CAPABILITY_PREDICATE
/// @dev These are the "make-or-break" tests: authority must die when the
///      verified state that justified it stops being true.
contract StateOracleTest is Test {
    EvidenceRegistry evidenceRegistry;
    PolicyRegistry policyRegistry;
    StateOracle stateOracle;
    CapabilityRegistry capabilityRegistry;
    CapabilityGuard capabilityGuard;
    AgentHistory agentHistory;

    address agent = makeAddr("agent");
    address verifier = makeAddr("verifier");

    bytes32 policyId = keccak256("CREDIT_STATE_BOUND");
    bytes32 action = keccak256("INCREASE_CREDIT");
    bytes32 sourceChain = keccak256("ethereum_mainnet");
    address sourceContract = makeAddr("usdc_source_contract");
    bytes32 evidenceRoot;
    bytes32 newEvidenceRoot;

    uint256 constant METRIC_COLLATERAL = uint256(keccak256("collateral_ratio"));
    uint256 constant METRIC_REPAYMENTS = uint256(keccak256("repayment_count"));
    bytes32 collatPredicate;
    bytes32 repayPredicate;

    uint64 constant SOURCE_BLOCK = 1_000_000;
    uint256 constant FRESHNESS = 600; // 10 minutes

    function setUp() public {
        evidenceRegistry = new EvidenceRegistry();
        policyRegistry = new PolicyRegistry();
        stateOracle = new StateOracle(FRESHNESS);
        stateOracle.setVerifier(verifier, true);

        capabilityRegistry = new CapabilityRegistry(address(policyRegistry), address(stateOracle));
        capabilityGuard = new CapabilityGuard(address(capabilityRegistry), address(stateOracle));
        agentHistory = new AgentHistory();

        policyRegistry.createPolicy(policyId, "Credit State Bound", 3, 20000, 16000, 25000, 600);

        // Predicate: collateral >= 150% (basis points: 15000)
        collatPredicate = stateOracle.createPredicate(METRIC_COLLATERAL, StateOracle.Operator.GTE, 15000);
        // Predicate: repayments >= 4
        repayPredicate = stateOracle.createPredicate(METRIC_REPAYMENTS, StateOracle.Operator.GTE, 4);

        evidenceRoot = keccak256("evidence-root-v1");
        newEvidenceRoot = keccak256("evidence-root-v2");

        // State currently justifies the capability:
        // collateral 181%, 4 repayments
        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, METRIC_COLLATERAL, 18100, SOURCE_BLOCK, evidenceRoot
        );
        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, METRIC_REPAYMENTS, 4, SOURCE_BLOCK, evidenceRoot
        );
    }

    function _createCapability(bytes32 sourceChain_, address sourceContract_, bytes32 predicate)
        internal
        returns (bytes32)
    {
        return capabilityRegistry.createCapability(
            agent, action, 25000, keccak256("merkle-root"), policyId, 600, sourceChain_, sourceContract_, predicate
        );
    }

    function _addCollateral(uint256 value, bytes32 root) internal {
        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, METRIC_COLLATERAL, value, SOURCE_BLOCK + 1, root
        );
    }

    // ========== POSITIVE: state satisfies predicate ==========

    function test_ExecutionSucceedsWithCurrentState() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);
        capabilityGuard.executeWithCapability(capId, agent, action, 25000, evidenceRoot);
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 0);
    }

    // ========== NEGATIVE: no observation ==========

    function test_ExecutionRevertsWhenNoObservation() public {
        // Capability bound to a (chain, contract) that has never been observed
        bytes32 capId = _createCapability(keccak256("arbitrum_never_observed"), makeAddr("nobody"), collatPredicate);
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, evidenceRoot);
    }

    // ========== NEGATIVE: predicate evaluated FALSE ==========

    function test_ExecutionRevertsWhenPredicateFalse() public {
        // Collateral drops 181% -> 138%: same predicate, same root, still false
        _addCollateral(13800, newEvidenceRoot);
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, newEvidenceRoot);
    }

    // ========== THE KILL TEST: stale root after state changed ==========

    function test_ExecutionRevertsWithStaleEvidenceRoot() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);

        // State moves forward: collateral still 181%, but a NEW evidence root
        // now commits to the newer cross-chain state.
        _addCollateral(18100, newEvidenceRoot);

        // Presenting the OLD proof root must fail even though the numeric
        // state never changed: the old root is stale.
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, evidenceRoot);

        // Presenting the CURRENT root succeeds.
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, newEvidenceRoot);
    }

    // ========== NEGATIVE: zero fresh proof ==========

    function test_ExecutionRevertsWhenNoFreshProof() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, bytes32(0));
    }

    // ========== NEGATIVE: observation too old ==========

    function test_ExecutionRevertsWhenObservationStale() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);
        // 11 minutes pass: observation exceeds the 10-minute freshness window
        vm.warp(block.timestamp + FRESHNESS + 1);
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, evidenceRoot);
    }

    // ========== NEGATIVE: unknown predicate ==========

    function test_ExecutionRevertsWhenPredicateUnknown() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, keccak256("forged-predicate"));
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, evidenceRoot);
    }

    // ========== NEGATIVE: wrong subject's state ==========

    function test_ExecutionRevertsWhenSubjectHasNoState() public {
        address other = makeAddr("other_agent");
        bytes32 capId = capabilityRegistry.createCapability(
            other, action, 25000, keccak256("merkle-root"), policyId, 600, sourceChain, sourceContract, collatPredicate
        );
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, other, action, 5000, evidenceRoot);
    }

    // ========== THE MONEY SHOT: same capability, state dies, authority dies ==========

    function test_StateDeteriorationKillsExistingCapability() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);

        // 1. Capability is valid, execution succeeds.
        capabilityGuard.executeWithCapability(capId, agent, action, 10000, evidenceRoot);
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 15000);

        // 2. Source-chain state deteriorates: collateral 181% -> 138%.
        _addCollateral(13800, newEvidenceRoot);

        // 3. Same capability, same agent, well within expiry. Execution MUST revert.
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, newEvidenceRoot);

        // 4. No state transition occurred.
        assertEq(capabilityRegistry.getRemainingAuthority(capId), 15000);
    }

    // ========== MULTI-SOURCE: all sources must satisfy ==========

    function test_MultiSourceCapabilityFailsIfAnySourceDies() public {
        address arbContract = makeAddr("arb_source_contract");
        bytes32 arbChain = keccak256("arbitrum_one");
        bytes32 arbRoot = keccak256("arb-evidence-v1");

        // Arbitrum state: collateral >= 150% is satisfied.
        vm.prank(verifier);
        stateOracle.recordStateObservation(
            arbChain, arbContract, agent, METRIC_COLLATERAL, 17500, SOURCE_BLOCK, arbRoot
        );

        // Capability bound to the Ethereum source.
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);

        // Ethereum state dies (collateral 138%): execution blocked despite
        // Arbitrum still being healthy.
        _addCollateral(13800, keccak256("eth-new-root"));

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, keccak256("eth-new-root"));

        // Sanity: the Arbitrum observation is still healthy on its own.
        assertTrue(stateOracle.checkStatePredicate(arbChain, arbContract, agent, collatPredicate, arbRoot));
    }

    // ========== Observed value is bound, not just root ==========

    function test_ThresholdBoundaryZero_OneBelow_OneAt() public {
        // Below threshold: 149.99% (14999 bp) fails.
        _addCollateral(14999, newEvidenceRoot);
        bytes32 capId = _createCapability(sourceChain, sourceContract, collatPredicate);
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, newEvidenceRoot);

        // At threshold: 150% (15000 bp) succeeds.
        _addCollateral(15000, keccak256("root-150"));
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, keccak256("root-150"));
    }

    // ========== Repayment count predicate ==========

    function test_RepaymentPredicateKillsCapabilityWhenCountDrops() public {
        bytes32 capId = _createCapability(sourceChain, sourceContract, repayPredicate);

        // Currently 4 repayments, valid.
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, evidenceRoot);

        // Rebalance: a default event rewrites repayment count to 0.
        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, METRIC_REPAYMENTS, 0, SOURCE_BLOCK + 5, newEvidenceRoot
        );

        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 5000, newEvidenceRoot);
    }
}
