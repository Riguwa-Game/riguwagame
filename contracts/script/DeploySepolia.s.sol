// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DoodleGate} from "../src/sepolia/DoodleGate.sol";

/// @notice Deploys the source-chain contract. Must run BEFORE Deploy.s.sol, because the ASC on
///         Creditcoin binds this address as the only emitter it will honour.
///
/// forge script script/DeploySepolia.s.sol --rpc-url sepolia --broadcast
contract DeploySepolia is Script {
    function run() external returns (address gate) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);
        gate = address(new DoodleGate(deployer));
        vm.stopBroadcast();

        console2.log("DOODLE_GATE_SEPOLIA=%s", gate);
    }
}
