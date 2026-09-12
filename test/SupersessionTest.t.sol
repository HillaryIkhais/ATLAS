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

/// @title SupersessionTest
/// @notice The hostile-judge test suite for the Drey-logic ATLAS.
/// @dev Core invariant:
///      EXECUTE(c)
///      ⇒
///      c.version = latestProvenVersion(c.authorityId)
///
///      If the source authorization advances (v41 → v42), any capability
///      still bound to v41 CANNOT execute, regardless of who holds it or
///      whether it is otherwise valid.
contract SupersessionTest is Test {
    // ─── Infrastructure ────────────────────────────────────────────────
    AtlasAuthorityController controller;
    MockBlockProver prover;
    AtlasAuthorityRegistry registry;
    AtlasCapabilities caps;
    AtlasExecutionGuard guard;
    AtlasLendingPool pool;

    // ─── Actors ────────────────────────────────────────────────────────
    address agent = makeAddr("agent");
    address subAgent = makeAddr("subAgent");
    address liquidity = makeAddr("liquidityProvider");
    address submitter = makeAddr("submitter");

    // ─── Shared constants ──────────────────────────────────────────────
    bytes32 constant ACTION_BORROW = keccak256("BORROW");
    uint256 constant AUTHORITY_ID = 1;
    uint256 constant TWO_HOURS = 2 hours;

    address sourceController;

    // ─── Setup ─────────────────────────────────────────────────────────

    function setUp() public {
        controller = new AtlasAuthorityController();
        sourceController = address(controller);

        prover = new MockBlockProver();
        registry = new AtlasAuthorityRegistry(address(prover));
        caps = new AtlasCapabilities(address(registry));
        pool = new AtlasLendingPool();
        guard = new AtlasExecutionGuard(address(registry), address(caps), address(pool));

        // Wire permissions
        registry.setController(sourceController, true);
        registry.setSubmitter(submitter, true);
        caps.setGuard(address(guard));
        pool.setGuard(address(guard));

        // Seed liquidity so borrows actually transfer funds
        vm.deal(liquidity, 1_000_000 ether);
        vm.prank(liquidity);
        pool.deposit{value: 1_000_000 ether}();
    }

    // ─── Helpers ───────────────────────────────────────────────────────

    function _createSourceAuthority(uint256 amount) internal returns (uint256 authId, uint64 version) {
        authId = controller.createAuthority(agent, ACTION_BORROW, amount, block.timestamp + TWO_HOURS);
        version = controller.latestVersion(authId);
    }

    function _narrowSourceAuthority(uint256 authId, uint256 newAmt) internal returns (uint64 version) {
        controller.narrowAuthority(authId, newAmt);
        version = controller.latestVersion(authId);
    }

    function _revokeSourceAuthority(uint256 authId) internal returns (uint64 version) {
        controller.revokeAuthority(authId);
        version = controller.latestVersion(authId);
    }

    /// @notice Simulate: source TX is mined → proof worker attests → proof submitted on Creditcoin.
    function _proveAuthorityUpdate(
        uint256 authId,
        uint64 version,
        uint256 maxAmt,
        uint256 exp,
        AuthorityTypes.Status status
    ) internal returns (bytes32 txHash) {
        txHash = keccak256(abi.encodePacked(authId, version, block.number));
        prover.attest(
            txHash,
            IUSCProver.ProvenAction({
                sourceContract: sourceController,
                authorityId: authId,
                agent: agent,
                action: ACTION_BORROW,
                maxAmount: maxAmt,
                expiresAt: exp,
                version: version,
                status: status
            })
        );
        // Worker submits proof on-chain (in production: the actual proof bytes)
        bytes memory proof = abi.encode(txHash);
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, txHash, block.number - 1, proof);
    }

    function _issueCapability(uint256 authId, uint64 version, uint256 maxAmt, uint256 exp)
        internal
        returns (uint256 capId)
    {
        vm.prank(agent);
        capId = caps.issueCapability(authId, agent, ACTION_BORROW, maxAmt, exp);
    }

    function _execute(uint256 capId, uint256 amount) internal returns (bool) {
        vm.prank(agent);
        try guard.execute(capId, ACTION_BORROW, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _executeAs(address subject, uint256 capId, uint256 amount) internal returns (bool) {
        vm.prank(subject);
        try guard.execute(capId, ACTION_BORROW, amount) {
            return true;
        } catch {
            return false;
        }
    }

    // ────────────────────────────────────────────────────────────────────
    //  1. HAPPY PATH — v41 borrow succeeds
    // ────────────────────────────────────────────────────────────────────

    function test_HappyPath_V41BorrowSucceeds() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);

        // Prove v1 on Creditcoin (first version = v1, but we call it "v1" for clarity)
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);

        uint256 capId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        bool ok = _execute(capId, 20_000e18);
        assertTrue(ok, "v41 borrow should succeed");
        assertEq(pool.getDebt(agent), 20_000e18, "debt must equal borrow amount");
    }

    // ────────────────────────────────────────────────────────────────────
    //  2. THE MONEY SHOT — v41 works, then v42 supersedes, v41 blocked
    // ────────────────────────────────────────────────────────────────────

    function test_Supersession_V42KillsV41Capability() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);

        // --- STATE A: prove v1, issue cap, borrow $20k ---
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 capId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);
        bool ok = _execute(capId, 20_000e18);
        assertTrue(ok, "first borrow should succeed");
        assertEq(pool.getDebt(agent), 20_000e18);

        // --- STATE B: Ethereum authorization narrowed $25k -> $10k ---
        uint64 v2 = _narrowSourceAuthority(authId, 10_000e18);

        // --- STATE C: prove v2 on Creditcoin ---
        _proveAuthorityUpdate(authId, v2, 10_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.NARROWED);

        // --- STATE D: same agent, same cap (v1), $5k request ---
        // Block 1: spending remaining 5k within v1's authority.
        // Wait — budget is 5k remaining ($25k-$20k), authority is $10k.
        // Capability authorizes $25k at v1; but execution guard compares v1 != v2=latest.
        // So even though remaining budget exists, the VERSION mismatch kills it.
        bool blocked = _execute(capId, 5_000e18);
        assertFalse(blocked, "v1 cap must be BLOCKED after v2 proven");

        // Verify guard reports the exact reason
        vm.prank(agent);
        (bool allowed, string memory reason,,) = guard.canExecute(capId, ACTION_BORROW, 5_000e18);
        assertFalse(allowed);
        assertEq(reason, "CAPABILITY_SUPERSEDED");

        // Debt unchanged.
        assertEq(pool.getDebt(agent), 20_000e18, "debt unchanged after blocked borrow");

        // New v2 cap: $10k, borrow $5k succeeds.
        uint256 newCapId = _issueCapability(authId, v2, 10_000e18, block.timestamp + TWO_HOURS);
        bool ok2 = _execute(newCapId, 5_000e18);
        assertTrue(ok2, "v2 borrow should succeed");
        assertEq(pool.getDebt(agent), 25_000e18);
    }

    // ────────────────────────────────────────────────────────────────────
    //  3. REVOKE — v2 active, v3 revoked, v2 cap blocked
    // ────────────────────────────────────────────────────────────────────

    function test_RevocationKillsExistingCapability() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);

        uint256 capId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        // Revoke at source (v2 = REVOKED)
        uint64 v3 = _revokeSourceAuthority(authId);
        _proveAuthorityUpdate(authId, v3, 0, 0, AuthorityTypes.Status.REVOKED);

        bool blocked = _execute(capId, 5_000e18);
        assertFalse(blocked, "v1 cap must be blocked after v3 revocation proved");
    }

    // ────────────────────────────────────────────────────────────────────
    //  4. STALE PROOF — prove v1 again after v2 is already proven
    // ────────────────────────────────────────────────────────────────────

    function test_StaleProof_RejectsReplayOfOldVersion() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);

        bytes32 tx1 = keccak256("tx-v1");
        bytes32 tx2 = keccak256("tx-v2");

        // v1 attested + proven
        prover.attest(
            tx1,
            IUSCProver.ProvenAction(
                sourceController,
                authId,
                agent,
                ACTION_BORROW,
                25_000e18,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, tx1, block.number - 1, abi.encode(tx1));

        // v2 attested + proven
        prover.attest(
            tx2,
            IUSCProver.ProvenAction(
                sourceController,
                authId,
                agent,
                ACTION_BORROW,
                10_000e18,
                block.timestamp + TWO_HOURS,
                2,
                AuthorityTypes.Status.NARROWED
            )
        );
        vm.prank(submitter);
        registry.proveAuthorityUpdate(authId, tx2, block.number - 1, abi.encode(tx2));

        // Replay v1: stale version → reverts
        vm.prank(submitter);
        vm.expectRevert(AtlasAuthorityRegistry.StaleVersion.selector);
        registry.proveAuthorityUpdate(authId, tx1, block.number, abi.encode(tx1));
    }

    // ────────────────────────────────────────────────────────────────────
    //  5. WRONG AGENT — capability holder != caller
    // ────────────────────────────────────────────────────────────────────

    function test_WrongAgent_Reverts() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 capId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        // Wrong agent tries to execute
        vm.prank(subAgent);
        vm.expectRevert(AtlasExecutionGuard.NotAgent.selector);
        guard.execute(capId, ACTION_BORROW, 5_000e18);
    }

    // ────────────────────────────────────────────────────────────────────
    //  6. UNTRUSTED SOURCE — proof from fake controller rejected
    // ────────────────────────────────────────────────────────────────────

    function test_UntrustedSource_ProofRejected() public {
        address fake = makeAddr("fakeController");
        bytes32 txHash = keccak256("fake-tx");
        prover.attest(
            txHash,
            IUSCProver.ProvenAction(
                fake, 1, agent, ACTION_BORROW, 25_000e18, block.timestamp + TWO_HOURS, 1, AuthorityTypes.Status.ACTIVE
            )
        );

        vm.prank(submitter);
        vm.expectRevert(AtlasAuthorityRegistry.UntrustedSource.selector);
        registry.proveAuthorityUpdate(1, txHash, block.number, abi.encode(txHash));
    }

    // ────────────────────────────────────────────────────────────────────
    //  7. WIDENING — capability issued above proven authority
    // ────────────────────────────────────────────────────────────────────

    function test_WideningCapability_Reverts() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);

        vm.prank(agent);
        // Issue $30k cap for a $25k authority → must be rejected at issuance.
        vm.expectRevert(AtlasCapabilities.ExceedsAuthority.selector);
        caps.issueCapability(authId, agent, ACTION_BORROW, 30_000e18, block.timestamp + TWO_HOURS);
    }

    // ────────────────────────────────────────────────────────────────────
    //  8. WRONG AUTHORITY ID — proof for #2 cannot advance #1
    // ────────────────────────────────────────────────────────────────────

    function test_WrongAuthorityId_ProofRejected() public {
        uint256 authId1 = controller.createAuthority(agent, ACTION_BORROW, 25_000e18, block.timestamp + TWO_HOURS);
        uint256 authId2 = controller.createAuthority(agent, ACTION_BORROW, 10_000e18, block.timestamp + TWO_HOURS);

        // Prove authId2 → version 1
        _proveAuthorityUpdate(authId2, 1, 10_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);

        // Try to advance authId1 using authId2's proof (id mismatch)
        // The prover already has authId2's txHash attested.
        // We construct a fresh tx for authId1 but with wrong id embedded...
        // Actually the ProvenAction.authorityId is checked against the function param.
        bytes32 txHash = keccak256("cross-id-attack");
        prover.attest(
            txHash,
            IUSCProver.ProvenAction(
                sourceController,
                authId2,
                agent,
                ACTION_BORROW,
                10_000e18,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );

        vm.prank(submitter);
        vm.expectRevert(AtlasAuthorityRegistry.StaleVersion.selector);
        registry.proveAuthorityUpdate(authId1, txHash, block.number, abi.encode(txHash));
    }

    // ────────────────────────────────────────────────────────────────────
    //  9. DELEGATION — non-widening enforced
    // ────────────────────────────────────────────────────────────────────

    function test_Delegation_NonWidening() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 parentId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        // Equal-to-parent delegation succeeds
        vm.prank(agent);
        uint256 childId = caps.delegateCapability(parentId, subAgent, 10_000e18, block.timestamp + 1 hours);
        AtlasCapabilities.Capability memory child = caps.getCapability(childId);
        assertEq(child.maxAmount, 10_000e18);
        assertEq(child.agent, subAgent);
        assertEq(child.authorityVersion, 1, "child inherits parent's authority version");

        // Sub-agent executes with its own cap
        vm.prank(subAgent);
        guard.execute(childId, ACTION_BORROW, 5_000e18);
        assertEq(pool.getDebt(subAgent), 5_000e18, "sub-agent borrow succeeded");

        // Parent's remaining budget reduced by the reserved amount at delegation time.
        AtlasCapabilities.Capability memory parentAfter = caps.getCapability(parentId);
        // parent.consumedAmount = 10_000e18 (reserved for child)
        assertEq(parentAfter.consumedAmount, 10_000e18, "parent reserves budget at delegation time");
        assertEq(parentAfter.maxAmount - parentAfter.consumedAmount, 15_000e18, "parent still has 15k for own use");
    }

    function test_Delegation_WideningAmount_Reverts() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 parentId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        vm.prank(agent);
        // $30k > parent's $25k authority
        vm.expectRevert(AtlasCapabilities.ExceedsAuthority.selector);
        caps.delegateCapability(parentId, subAgent, 30_000e18, block.timestamp + 1 hours);
    }

    // ────────────────────────────────────────────────────────────────────
    //  10. SUPERSESSION KILLS CHILD TOO
    // ────────────────────────────────────────────────────────────────────

    function test_SupersessionKillsDelegatedCapability() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);

        uint256 parentId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);
        vm.prank(agent);
        uint256 childId = caps.delegateCapability(parentId, subAgent, 10_000e18, block.timestamp + 1 hours);

        // Child borrows successfully under v1
        vm.prank(subAgent);
        guard.execute(childId, ACTION_BORROW, 5_000e18);
        assertEq(pool.getDebt(subAgent), 5_000e18);

        // Authority narrowed to v2
        uint64 v2 = _narrowSourceAuthority(authId, 10_000e18);
        _proveAuthorityUpdate(authId, v2, 10_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.NARROWED);

        // Child (still v1) tries again → blocked
        bool blocked = _executeAs(subAgent, childId, 3_000e18);
        assertFalse(blocked, "child capability blocked by v2 supersession");

        vm.prank(subAgent);
        (bool allowed, string memory reason,,) = guard.canExecute(childId, ACTION_BORROW, 3_000e18);
        assertFalse(allowed);
        assertEq(reason, "CAPABILITY_SUPERSEDED");
    }

    // ────────────────────────────────────────────────────────────────────
    //  11. INSUFFICIENT BUDGET — replay prevention within version
    // ────────────────────────────────────────────────────────────────────

    function test_ReplayPrevention_InsufficientBudget() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 capId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        // Borrow full $25k in two calls
        assertTrue(_execute(capId, 20_000e18));
        assertTrue(_execute(capId, 5_000e18));

        // Third call: zero remaining
        assertFalse(_execute(capId, 1_000e18), "must reject over-budget within same version");
    }

    // ────────────────────────────────────────────────────────────────────
    //  12. REAL LENDING STATE — deposit / borrow / repay / balance
    // ────────────────────────────────────────────────────────────────────

    function test_LendingPool_Accounting() public {
        (uint256 authId,) = _createSourceAuthority(10_000e18);
        _proveAuthorityUpdate(authId, 1, 10_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 capId = _issueCapability(authId, 1, 10_000e18, block.timestamp + TWO_HOURS);

        uint256 agentBalBefore = agent.balance;
        assertTrue(_execute(capId, 7 ether));

        // Agent received 7 ETH
        assertEq(agent.balance, agentBalBefore + 7 ether);
        assertEq(pool.getDebt(agent), 7 ether);
        assertEq(pool.liquidity(), 1_000_000 ether - 7 ether);

        // Agent repays
        vm.deal(agent, 7 ether);
        vm.prank(agent);
        pool.repay{value: 7 ether}();
        assertEq(pool.getDebt(agent), 0);
        assertEq(pool.liquidity(), 1_000_000 ether);
    }

    // ────────────────────────────────────────────────────────────────────
    //  13. CAN-EXECUTE QUERY — the SDK's underlying view
    // ────────────────────────────────────────────────────────────────────

    function test_CanExecute_ViewMatchesExecution() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        _proveAuthorityUpdate(authId, 1, 25_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.ACTIVE);
        uint256 capId = _issueCapability(authId, 1, 25_000e18, block.timestamp + TWO_HOURS);

        vm.prank(agent);
        (bool allowed,,,) = guard.canExecute(capId, ACTION_BORROW, 5_000e18);
        assertTrue(allowed, "canExecute must agree before supersession");

        // Advance
        uint64 v2 = _narrowSourceAuthority(authId, 10_000e18);
        _proveAuthorityUpdate(authId, v2, 10_000e18, block.timestamp + TWO_HOURS, AuthorityTypes.Status.NARROWED);

        vm.prank(agent);
        (bool stillAllowed, string memory reason,,) = guard.canExecute(capId, ACTION_BORROW, 5_000e18);
        assertFalse(stillAllowed);
        assertEq(reason, "CAPABILITY_SUPERSEDED");
    }

    // ────────────────────────────────────────────────────────────────────
    //  14. EXPLOIT ATTEMPT — deploy fake controller, register, try to
    //      advance authority with fabricated proof
    // ────────────────────────────────────────────────────────────────────

    function test_ForgedController_BlockedByTrustedSourceCheck() public {
        AtlasAuthorityController fakeCtrl = new AtlasAuthorityController();
        uint256 fakeAuthId = fakeCtrl.createAuthority(agent, ACTION_BORROW, 100_000e18, block.timestamp + TWO_HOURS);

        // Worker "attests" a fake proof
        bytes32 txHash = keccak256("forged-tx");
        prover.attest(
            txHash,
            IUSCProver.ProvenAction(
                address(fakeCtrl),
                fakeAuthId,
                agent,
                ACTION_BORROW,
                100_000e18,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );

        // Submit: untrusted controller → revert
        vm.prank(submitter);
        vm.expectRevert(AtlasAuthorityRegistry.UntrustedSource.selector);
        registry.proveAuthorityUpdate(fakeAuthId, txHash, block.number, abi.encode(txHash));
    }

    // ────────────────────────────────────────────────────────────────────
    //  15. ZERO PROOF — raw tx hash without proof payload rejected
    // ────────────────────────────────────────────────────────────────────

    function test_ZeroProofLength_Reverts() public {
        (uint256 authId,) = _createSourceAuthority(25_000e18);
        bytes32 txHash = keccak256("no-proof");
        prover.attest(
            txHash,
            IUSCProver.ProvenAction(
                sourceController,
                authId,
                agent,
                ACTION_BORROW,
                25_000e18,
                block.timestamp + TWO_HOURS,
                1,
                AuthorityTypes.Status.ACTIVE
            )
        );

        vm.prank(submitter);
        vm.expectRevert(AtlasAuthorityRegistry.InvalidProof.selector);
        registry.proveAuthorityUpdate(authId, txHash, block.number, bytes(""));
    }
}
