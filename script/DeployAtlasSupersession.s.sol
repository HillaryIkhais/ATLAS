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

/// @title DeployAtlasSupersession
/// @notice Deploy the full supersession stack on an EVM chain (Anvil/CC3).
/// @dev Prints addresses to stdout. Wire-up order matters: the lending pool is
///      constructed first (no args), then the guard, then `setGuard` on the
///      pool and caps to break the circular dependency.
contract DeployAtlasSupersession is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AtlasAuthorityController controller = new AtlasAuthorityController();
        console.log("AtlasAuthorityController:", address(controller));

        MockBlockProver prover = new MockBlockProver();
        console.log("MockBlockProver:", address(prover));

        AtlasAuthorityRegistry registry = new AtlasAuthorityRegistry(address(prover));
        console.log("AtlasAuthorityRegistry:", address(registry));

        AtlasCapabilities caps = new AtlasCapabilities(address(registry));
        console.log("AtlasCapabilities:", address(caps));

        AtlasLendingPool pool = new AtlasLendingPool();
        console.log("AtlasLendingPool:", address(pool));

        AtlasExecutionGuard guard = new AtlasExecutionGuard(address(registry), address(caps), address(pool));
        console.log("AtlasExecutionGuard:", address(guard));

        caps.setGuard(address(guard));
        pool.setGuard(address(guard));

        // Trust wiring: the deployed controller is the only trusted source,
        // and only the deployer may submit attestation proofs (P2 upgrades the
        // MockBlockProver to the real USC/BlockProver adapter).
        registry.setController(address(controller), true);
        registry.setSubmitter(vm.addr(deployerPrivateKey), true);

        vm.stopBroadcast();

        console.log("\n=== ATLAS SUPERSESSION DEPLOYED ===");
        console.log("controller:", address(controller));
        console.log("prover:    ", address(prover));
        console.log("registry:  ", address(registry));
        console.log("caps:      ", address(caps));
        console.log("pool:      ", address(pool));
        console.log("guard:     ", address(guard));
    }
}
