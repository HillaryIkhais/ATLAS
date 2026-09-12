// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/common/AuthorityTypes.sol";
import "../contracts/AtlasAuthorityController.sol";
import "../contracts/AtlasAuthorityRegistry.sol";
import "../contracts/AtlasCapabilities.sol";
import "../contracts/AtlasExecutionGuard.sol";
import "../contracts/AtlasLendingPool.sol";
import "../contracts/MockBlockProver.sol";

/// @title RunSupersessionScenario
/// @notice Replay the Drey-money-shot on Anvil and print the trace.
///
///  THE MONEY SHOT (locked demo):
///    agent holds capability #1 => BORROW <= $25k (authority v1, "v41")
///    borrow $20k                 -> SUCCESS
///    source narrows to $10k      -> v2 ("v42")
///    proof attested + proven
///    capability #1 tries $5k     -> CAPABILITY_SUPERSEDED, REVERT
///    new capability #2 (v2) borrows $5k -> SUCCESS
///
/// @dev Two broadcast phases keep the forge broadcaster's nonce tracking sane:
///      Phase 1 (deployer): deploy + wire + liquidity.
///      Phase 2 (agent):    authority, proofs, capabilities, borrows.
///      The deliberately-reverting attempt and the `canExecute` views run
///      outside the broadcast (reverts produce no blockspace anyway).
///      P2 replaces MockBlockProver with the real Attestcoin/USC proof adapter.
contract RunSupersessionScenario is Script {
    // Anvil dev keys (public test keys, safe to hardcode for local demo).
    uint256 internal constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant AGENT_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    address internal constant AGENT = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    bytes32 internal constant ACTION_BORROW = keccak256("BORROW");
    uint256 internal constant TWO_HOURS = 2 hours;
    uint256 internal constant PRINCIPAL = 1_000 ether;

    AtlasAuthorityController internal controller;
    MockBlockProver internal prover;
    AtlasAuthorityRegistry internal registry;
    AtlasCapabilities internal caps;
    AtlasExecutionGuard internal guard;
    AtlasLendingPool internal pool;
    address internal deployer;

    function run() external {
        deployer = vm.addr(DEPLOYER_KEY);

        // ── PHASE 1 (deployer): deploy + wire the whole stack ─────────
        vm.startBroadcast(DEPLOYER_KEY);
        controller = new AtlasAuthorityController();
        prover = new MockBlockProver();
        registry = new AtlasAuthorityRegistry(address(prover));
        caps = new AtlasCapabilities(address(registry));
        pool = new AtlasLendingPool();
        guard = new AtlasExecutionGuard(address(registry), address(caps), address(pool));
        caps.setGuard(address(guard));
        pool.setGuard(address(guard));
        registry.setController(address(controller), true);
        // The agent doubles as proof submitter here; the deployer seeds liquidity.
        registry.setSubmitter(AGENT, true);
        pool.deposit{value: PRINCIPAL}();
        vm.stopBroadcast();
        console.log("pool.liquidity =", pool.liquidity());

        // ── PHASE 2 (agent): authority -> proof -> capability -> borrow ─
        vm.startBroadcast(AGENT_KEY);

        // ACT I: authority v1 created at the source (the "$41" story).
        uint256 authId = controller.createAuthority(AGENT, ACTION_BORROW, 25 ether, block.timestamp + TWO_HOURS);
        console.log("AUTHORITY v1 created  (BORROW <= $25k)  id=", authId);

        _attestProve(authId, 1, 25 ether, AuthorityTypes.Status.ACTIVE);
        console.log("version 1 proven on-chain");

        uint256 cap1 = caps.issueCapability(authId, AGENT, ACTION_BORROW, 25 ether, block.timestamp + TWO_HOURS);
        console.log("capability #1 issued  [v1/$25k]  capId=", cap1);

        guard.execute(cap1, ACTION_BORROW, 20 ether);
        console.log("BORROW 20k via cap#1 SUCCESS; debt=", pool.getDebt(AGENT));

        // ACT II: authority narrows to $10k (v1 -> v2, "v41 -> v42").
        controller.narrowAuthority(authId, 10 ether);
        console.log("AUTHORITY narrowed to $10k ......... at source");

        _attestProve(authId, 2, 10 ether, AuthorityTypes.Status.NARROWED);
        console.log("version 2 proven on-chain");
        console.log("registry.latestProvenVersion=", uint256(registry.latestProvenVersion(authId)));

        // ACT IV: fresh capability bound to v2 executes fine.
        uint256 cap2 = caps.issueCapability(authId, AGENT, ACTION_BORROW, 10 ether, block.timestamp + TWO_HOURS);
        console.log("new capability #2 issued [v2/$10k]  capId=", cap2);

        guard.execute(cap2, ACTION_BORROW, 5 ether);
        console.log("BORROW 5k via cap#2 SUCCESS; debt=", pool.getDebt(AGENT));
        vm.stopBroadcast();

        // ── ACT III (post-broadcast): THE MONEY SHOT ────────────────────
        // The v1 capability is still live on-chain. Prove it can no longer
        // execute — outside the broadcast, since reverts produce no blockspace.
        console.log("\n--- MONEY SHOT CHECK (simulated, on-chain state) ---");
        _printCanExecute(cap1, 5 ether);
        _tryBorrowAndDecode(cap1, 5 ether);
        console.log("\n=== MONEY SHOT COMPLETE ===");
        console.log("source v1/v2 amounts committed on-chain; old capability dead, new one alive");
    }

    // ────────────────────────────────────────────────────────────────
    // Helpers
    // ────────────────────────────────────────────────────────────────

    function _attestProve(uint256 authId, uint64 version, uint256 amount, AuthorityTypes.Status status) internal {
        bytes32 txHash = keccak256(abi.encode(authId, version, "attestcoin"));
        prover.attest(
            txHash,
            IUSCProver.ProvenAction(
                address(controller), authId, AGENT, ACTION_BORROW, amount, block.timestamp + TWO_HOURS, version, status
            )
        );
        registry.proveAuthorityUpdate(authId, txHash, block.number, abi.encode(txHash));
    }

    function _printCanExecute(uint256 capId, uint256 amount) internal {
        // `canExecute` is view, but its agent check reads msg.sender.
        vm.prank(AGENT);
        (bool allowed, string memory reason, uint64 capV, uint64 latestV) =
            guard.canExecute(capId, ACTION_BORROW, amount);
        console.log("  canExecute: capId=", capId, " amount=", amount);
        console.log("  allowed=", allowed, " reason=", reason);
        console.log("  capV=", uint256(capV), " latestV=", uint256(latestV));
    }

    /// @notice Attempt borrow as the agent WITHOUT broadcasting (the tx is
    ///         expected to revert, and reverts produce no blockspace). The
    ///         revert data is captured and decoded to show CAPABILITY_SUPERSEDED.
    function _tryBorrowAndDecode(uint256 capId, uint256 amount) internal {
        vm.prank(AGENT);
        (bool ok, bytes memory data) =
            address(guard).call(abi.encodeCall(guard.execute, (capId, ACTION_BORROW, amount)));
        if (ok) {
            console.log("BORROW amount=", amount, " via cap=", capId);
            console.log("UNEXPECTED SUCCESS");
            return;
        }
        if (data.length >= 68 && bytes4(data) == AtlasExecutionGuard.CapabilitySuperseded.selector) {
            // `CapabilitySuperseded(uint64,uint64)` = selector + two 32-byte words.
            bytes memory payload = new bytes(64);
            assembly {
                mstore(add(payload, 32), mload(add(data, 36)))
                mstore(add(payload, 64), mload(add(data, 68)))
            }
            (uint64 capVersion, uint64 latestVersion) = abi.decode(payload, (uint64, uint64));
            console.log("BORROW amount=", amount, " via cap=", capId);
            console.log("BLOCKED: CAPABILITY_SUPERSEDED");
            console.log("capability carries v", uint256(capVersion), " but latest proven is v", uint256(latestVersion));
        } else {
            console.log("BORROW amount=", amount, " via cap=", capId);
            console.log("REVERTED (unexpected reason)");
        }
    }
}
