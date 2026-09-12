// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/common/AuthorityTypes.sol";
import "../contracts/AtlasAuthorityController.sol";
import "../contracts/AtlasAuthorityRegistry.sol";
import "../contracts/AtlasCapabilities.sol";
import "../contracts/AtlasExecutionGuard.sol";
import "../contracts/AtlasLendingPool.sol";
import "../contracts/MockBlockProver.sol";

/// @title SupersessionProperties
/// @notice Property/fuzz tests for the Drey-logic ATLAS invariants.
/// @dev The four properties this protocol must guarantee for EVERY reachable
///      state, regardless of inputs:
///        1. never(version decreases)
///        2. never(child > parent)
///        3. never(old capability executes after newer proven version)
///        4. never(unproven source transition changes registry)
///        5. never(wrong agent executes capability)
contract SupersessionProperties is Test {
    AtlasAuthorityController controller;
    MockBlockProver prover;
    AtlasAuthorityRegistry registry;
    AtlasCapabilities caps;
    AtlasExecutionGuard guard;
    AtlasLendingPool pool;

    address agent = makeAddr("agent");
    address subAgent = makeAddr("subAgent");
    address liquidity = makeAddr("liquidityProvider");
    address submitter = makeAddr("submitter");

    bytes32 constant ACTION_BORROW = keccak256("BORROW");
    uint256 constant TWO_HOURS = 2 hours;

    function setUp() public {
        controller = new AtlasAuthorityController();
        prover = new MockBlockProver();
        registry = new AtlasAuthorityRegistry(address(prover));
        caps = new AtlasCapabilities(address(registry));
        pool = new AtlasLendingPool();
        guard = new AtlasExecutionGuard(address(registry), address(caps), address(pool));

        registry.setController(address(controller), true);
        registry.setSubmitter(submitter, true);
        caps.setGuard(address(guard));
        pool.setGuard(address(guard));

        vm.deal(liquidity, 1_000_000 ether);
        vm.prank(liquidity);
        pool.deposit{value: 1_000_000 ether}();
    }

    /// @notice PROPERTY 1 + 3: version is monotonic AND a capability bound to an
    ///         old version can never execute once a newer version is proven.
    /// @param amt1 First authority amount (fuzzed).
    /// @param amt2 Second (narrowed) authority amount.
    /// @param borrow  Fuzzed borrow amount.
    function testFuzz_SupersessionBlocksOldVersion(uint64 amt1, uint64 amt2, uint64 borrow) public {
        if (amt1 == 0) amt1 = 1 ether;
        if (amt2 >= amt1) amt2 = amt1 / 2;

        uint256 authId = controller.createAuthority(agent, ACTION_BORROW, amt1, block.timestamp + TWO_HOURS);

        // Prove v1
        bytes32 tx1 = keccak256(abi.encode(authId, uint64(1), "v1"));
        prover.attest(
            tx1,
            IUSCProver.ProvenAction(
                address(controller),
                authId,
                agent,
                ACTION_BORROW,
                amt1,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, tx1, block.number, abi.encode(tx1));

        // Issue v1 capability
        vm.prank(agent);
        uint256 capId = caps.issueCapability(authId, agent, ACTION_BORROW, amt1, block.timestamp + TWO_HOURS);

        // v2 at source: narrowed (amount > 0) or revoked (amount == 0).
        uint64 v2;
        uint256 v2Amount;
        bytes32 tx2;
        AuthorityTypes.Status v2Status;
        if (amt2 == 0) {
            controller.revokeAuthority(authId);
            v2Amount = 0;
            v2Status = AuthorityTypes.Status.REVOKED;
        } else {
            uint256 target = amt2 % amt1; // < amt1, narrowing valid when > 0
            if (target == 0) target = 1;
            controller.narrowAuthority(authId, target);
            v2Amount = target;
            v2Status = AuthorityTypes.Status.NARROWED;
        }
        v2 = controller.latestVersion(authId);
        tx2 = keccak256(abi.encode(authId, uint64(2), v2Amount, uint256(v2Status)));
        prover.attest(
            tx2,
            IUSCProver.ProvenAction(
                address(controller), authId, agent, ACTION_BORROW, v2Amount, block.timestamp + TWO_HOURS, 2, v2Status
            )
        );
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, tx2, block.number, abi.encode(tx2));

        // Sanity: version cannot decrease on ANY subsequent proven update.
        assertEq(registry.latestProvenVersion(authId), v2);
        assertLt(uint256(1), uint256(registry.latestProvenVersion(authId)), "version strictly increases");

        // The v1 cap must NEVER execute, for any borrow amount, even though
        // the agent legitimately holds it.  Keep the amount inside budget so
        // the ONLY possible rejection is the version check.
        uint256 inBudget = (borrow % amt1) + 1;
        vm.expectRevert(abi.encodeWithSelector(AtlasExecutionGuard.CapabilitySuperseded.selector, uint64(1), uint64(2)));
        vm.prank(agent);
        guard.execute(capId, ACTION_BORROW, inBudget);
    }

    /// @notice PROPERTY 2: child authority can never exceed the parent.
    /// @param parentAmount Parent authority amount (fuzzed).
    /// @param childAmount  Attempted child delegation amount.
    function testFuzz_ChildNeverExceedsParent(uint64 parentAmount, uint64 childAmount) public {
        if (parentAmount == 0) parentAmount = 1 ether;

        uint256 authId = controller.createAuthority(agent, ACTION_BORROW, parentAmount, block.timestamp + TWO_HOURS);
        bytes32 tx1 = keccak256(abi.encode(authId, "delegation-tx"));
        prover.attest(
            tx1,
            IUSCProver.ProvenAction(
                address(controller),
                authId,
                agent,
                ACTION_BORROW,
                parentAmount,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, tx1, block.number, abi.encode(tx1));

        vm.prank(agent);
        uint256 parentCap =
            caps.issueCapability(authId, agent, ACTION_BORROW, parentAmount, block.timestamp + TWO_HOURS);

        // If child amount is within parent, delegation succeeds and the child
        // capability can NEVER carry more authority than the parent's remaining.
        vm.prank(agent);
        if (childAmount > 0 && childAmount <= parentAmount) {
            uint256 childCap = caps.delegateCapability(parentCap, subAgent, childAmount, block.timestamp + 1 hours);
            AtlasCapabilities.Capability memory child = caps.getCapability(childCap);
            AtlasCapabilities.Capability memory parent = caps.getCapability(parentCap);
            assertLe(child.maxAmount, parentAmount, "child never exceeds parent authority");
            assertLe(parent.consumedAmount, parent.maxAmount, "delegation reservation never exceeds parent budget");
            assertEq(child.authorityVersion, parent.authorityVersion, "child inherits parent version");
        } else {
            vm.expectRevert();
            caps.delegateCapability(parentCap, subAgent, childAmount, block.timestamp + 1 hours);
        }
    }

    /// @notice PROPERTY 4: an unproven source transition must never change the registry.
    /// @param version A fuzzed version number.
    function testFuzz_UnprovenSourceCannotTouchRegistry(uint64 version) public {
        // Collision-avoid a plausible (but unattested) tx hash.
        bytes32 phantomTx = keccak256(abi.encode("phantom", version));

        // No `prover.attest` has been called for phantomTx.
        vm.prank(submitter);
        vm.expectRevert(AtlasAuthorityRegistry.InvalidProof.selector);
        registry.proveAuthorityUpdate(1, phantomTx, block.number, abi.encode(phantomTx));

        // Registry untouched.
        assertEq(uint256(registry.getProvenAuthority(1).version), uint256(0));
        uint256 count = registry.provenanceCount();
        assertEq(count, uint256(0), "no provenance changes without a valid proof");
    }

    /// @notice PROPERTY 4b: a valid proof for an untrusted source contract is rejected.
    function testFuzz_UntrustedSourceRejected(bytes32 seed) public {
        address fakeController = makeAddr("fake_controller");
        bytes32 txHash = keccak256(abi.encode(seed, "fake"));
        prover.attest(
            txHash,
            IUSCProver.ProvenAction(
                fakeController,
                1,
                agent,
                ACTION_BORROW,
                1 ether,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );

        vm.prank(submitter);
        vm.expectRevert();
        registry.proveAuthorityUpdate(1, txHash, block.number, abi.encode(txHash));

        assertEq(registry.getProvenAuthority(1).version, 0, "untrusted source cannot advance registry");
    }

    /// @notice PROPERTY 5: execution is impossible for anyone who isn't the capability holder.
    /// @param amount Fuzzed amount; all must be rejected for a non-holder.
    function testFuzz_NonHolderCannotExecute(uint64 amount) public {
        uint256 amt = amount % 1000 ether;
        uint256 authId = controller.createAuthority(agent, ACTION_BORROW, amt + 1 ether, block.timestamp + TWO_HOURS);
        bytes32 tx1 = keccak256(abi.encode(authId, "tx", amt));
        prover.attest(
            tx1,
            IUSCProver.ProvenAction(
                address(controller),
                authId,
                agent,
                ACTION_BORROW,
                amt + 1 ether,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, tx1, block.number, abi.encode(tx1));

        vm.prank(agent);
        uint256 capId = caps.issueCapability(authId, agent, ACTION_BORROW, amt + 1 ether, block.timestamp + TWO_HOURS);

        // Wrong agent (not the holder)
        vm.prank(subAgent);
        vm.expectRevert(AtlasExecutionGuard.NotAgent.selector);
        guard.execute(capId, ACTION_BORROW, amt);
    }
}
