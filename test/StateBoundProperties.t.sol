// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PolicyRegistry.sol";
import "../contracts/CapabilityRegistry.sol";
import "../contracts/CapabilityGuard.sol";
import "../contracts/StateOracle.sol";

/// @title StateBoundProperties
/// @notice Property/fuzz tests for the ATLAS core invariants.
/// @dev The monster property is: THERE EXISTS NO REACHABLE EXECUTION STATE IN
///      WHICH ATLAS EXECUTES AN ACTION WHILE ITS AUTHORIZATION PREDICATE IS
///      FALSE. We fuzz arbitrarily across observed state and thresholds and
///      assert execution always agrees with the predicate.
contract StateBoundProperties is Test {
    PolicyRegistry policyRegistry;
    StateOracle stateOracle;
    CapabilityRegistry capabilityRegistry;
    CapabilityGuard capabilityGuard;

    address agent = makeAddr("agent");
    address verifier = makeAddr("verifier");

    bytes32 policyId = keccak256("CREDIT_V1");
    bytes32 action = keccak256("INCREASE_CREDIT");
    bytes32 sourceChain = keccak256("ethereum_mainnet");
    address sourceContract = makeAddr("usdc_source");
    bytes32 root = keccak256("fuzz-root");

    uint256 constant MAX_AUTH = 1e27;
    uint256 constant FRESHNESS = 600;

    bytes32 predicateGTE;

    function setUp() public {
        policyRegistry = new PolicyRegistry();
        stateOracle = new StateOracle(FRESHNESS);
        stateOracle.setVerifier(verifier, true);
        capabilityRegistry = new CapabilityRegistry(address(policyRegistry), address(stateOracle));
        capabilityGuard = new CapabilityGuard(address(capabilityRegistry), address(stateOracle));
        policyRegistry.createPolicy(policyId, "Credit V1", 3, 20000, 16000, MAX_AUTH, 600);
    }

    /// @notice MONSTER: execution never happens while predicate is false.
    /// @param observed  Any observed collateral value [0, 2^64)
    /// @param threshold Any threshold        [0, 2^64)
    /// @dev Expects: consume(amount) == (observed >= threshold), for every seed.
    function testFuzz_ExecutionAgreesWithPredicate(uint64 observed, uint64 threshold) public {
        // Fresh observation under a dedicated root per seed.
        bytes32 obsRoot = keccak256(abi.encode(observed, threshold));
        predicateGTE =
            stateOracle.createPredicate(uint256(keccak256("collateral")), StateOracle.Operator.GTE, threshold);

        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, uint256(keccak256("collateral")), observed, 1, obsRoot
        );

        bytes32 capId = capabilityRegistry.createCapability(
            agent, action, MAX_AUTH, keccak256("merkle"), policyId, 600, sourceChain, sourceContract, predicateGTE
        );

        uint256 before = capabilityRegistry.getRemainingAuthority(capId);
        bool shouldSucceed = observed >= threshold;

        if (shouldSucceed) {
            capabilityGuard.executeWithCapability(capId, agent, action, 1000, obsRoot);
            assertLt(capabilityRegistry.getRemainingAuthority(capId), before, "authority consumed on success");
        } else {
            vm.expectRevert("CapabilityGuard: validation failed");
            capabilityGuard.executeWithCapability(capId, agent, action, 1000, obsRoot);
            assertEq(capabilityRegistry.getRemainingAuthority(capId), before, "no consumption on rejected execution");
        }
    }

    /// @notice Delegation is non-widening for EVERY child amount:
    ///         success iff childAmount <= parentRemaining.
    function testFuzz_DelegationNeverWidens(uint64 parentAmount, uint64 childAmount) public {
        if (parentAmount == 0) return;

        bytes32 root2 = keccak256(abi.encode(parentAmount, childAmount, "delegation"));
        predicateGTE = stateOracle.createPredicate(uint256(keccak256("debt")), StateOracle.Operator.LTE, 999);

        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, uint256(keccak256("debt")), 500, 1, root2
        );

        bytes32 parentCapId = capabilityRegistry.createCapability(
            agent, action, parentAmount, keccak256("merkle"), policyId, 600, sourceChain, sourceContract, predicateGTE
        );

        // Parent has full remaining authority (nothing consumed).
        bool shouldSucceed = childAmount > 0 && childAmount <= parentAmount;

        vm.prank(agent);
        if (shouldSucceed) {
            bytes32 childCapId = capabilityRegistry.delegateCapability(parentCapId, makeAddr("sub"), childAmount, 300);
            assertLe(
                capabilityRegistry.getCapability(childCapId).maxAmount,
                capabilityRegistry.getCapability(parentCapId).maxAmount,
                "child authority exceeds parent"
            );
        } else {
            vm.expectRevert();
            capabilityRegistry.delegateCapability(parentCapId, makeAddr("sub"), childAmount, 300);
        }
    }

    /// @notice Arithmetic consistency: checkStatePredicate is equivalent to
    ///         direct threshold comparison for GTE over recorded observations.
    function testFuzz_OracleMatchesArithmetic(uint64 observed, uint64 threshold) public {
        bytes32 p = stateOracle.createPredicate(uint256(keccak256("metric")), StateOracle.Operator.GTE, threshold);
        uint256 obsRoot2 = uint256(keccak256(abi.encode(observed, threshold, block.timestamp)));
        vm.prank(verifier);
        stateOracle.recordStateObservation(
            sourceChain, sourceContract, agent, uint256(keccak256("metric")), observed, 1, bytes32(obsRoot2)
        );

        bool oracle = stateOracle.checkStatePredicate(sourceChain, sourceContract, agent, p, bytes32(obsRoot2));
        assertEq(oracle, observed >= threshold, "oracle must be exactly observed >= threshold");
    }

    /// @notice Authority only ever decreases as a commitment is consumed.
    function testFuzz_AuthorityMonotonic(uint64 amountA, uint64 amountB, uint64 maxAmt) public {
        if (maxAmt == 0) return;
        bytes32 pRoot = keccak256(abi.encode(maxAmt, "monotonic"));
        bytes32 p = stateOracle.createPredicate(uint256(keccak256("c")), StateOracle.Operator.GTE, 100);
        vm.prank(verifier);
        stateOracle.recordStateObservation(sourceChain, sourceContract, agent, uint256(keccak256("c")), 200, 1, pRoot);

        bytes32 capId = capabilityRegistry.createCapability(
            agent, action, maxAmt, keccak256("merkle"), policyId, 600, sourceChain, sourceContract, p
        );

        (uint256 a, uint256 b) = (uint256(amountA), uint256(amountB));
        // Execute a then b, each only if within remaining; assert remaining never jumps up.
        uint256 remaining = capabilityRegistry.getRemainingAuthority(capId);
        if (a > 0 && a <= remaining) {
            capabilityGuard.executeWithCapability(capId, agent, action, a, pRoot);
        }
        uint256 remainingAfterA = capabilityRegistry.getRemainingAuthority(capId);
        assertLe(remainingAfterA, maxAmt, "authority must be monotonically non-increasing");

        if (a > 0 && a <= maxAmt && b > 0 && b <= remainingAfterA) {
            capabilityGuard.executeWithCapability(capId, agent, action, b, pRoot);
        }
        uint256 remainingAfterB = capabilityRegistry.getRemainingAuthority(capId);
        assertLe(remainingAfterB, remainingAfterA, "authority must never increase");
    }

    /// @notice An unknown predicate can never pass, regardless of inputs.
    function testFuzz_ForgedPredicateAlwaysFails(bytes32 forgedHash, uint64 amount) public {
        bytes32 capId = capabilityRegistry.createCapability(
            agent,
            action,
            MAX_AUTH,
            keccak256("merkle"),
            policyId,
            600,
            sourceChain,
            sourceContract,
            forgedHash == bytes32(0) ? keccak256("forged") : forgedHash
        );
        vm.expectRevert("CapabilityGuard: validation failed");
        capabilityGuard.executeWithCapability(capId, agent, action, 1, keccak256("any-root"));
    }
}
