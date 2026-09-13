// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/usc/MockUSCProver.sol";
import "../contracts/AtlasAuthorityRegistry.sol";

contract DeployUSC is Script {
    function run() external {
        uint64 sourceChainKey = 11155111;
        address authorizedController = vm.envAddress("AUTHORIZED_CONTROLLER");
        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployer);

        MockUSCProver prover = new MockUSCProver(sourceChainKey, authorizedController);
        AtlasAuthorityRegistry registry = new AtlasAuthorityRegistry(address(prover));

        registry.setController(authorizedController, true);
        registry.setSubmitter(deployer, true);

        vm.stopBroadcast();

        console.log("MockUSCProver:", address(prover));
        console.log("AtlasAuthorityRegistry:", address(registry));
    }
}
