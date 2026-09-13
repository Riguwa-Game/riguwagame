// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";

/// @notice Deploys the four Creditcoin proxies and wires them together.
///
/// Run DeploySepolia.s.sol first and put its address in DOODLE_GATE_SEPOLIA: without it the ASC
/// has no registered emitter and every cross-chain query will be refused.
///
/// forge script script/Deploy.s.sol --rpc-url creditcoin_testnet --broadcast
contract Deploy is Script {
    uint64 constant SEPOLIA_CHAIN_KEY = 1; // Attestcoin chainKey, not 11155111

    uint256 constant MAX_STAKE_NATIVE = 100e18;
    uint256 constant MAX_STAKE_USDT = 100e6;
    uint256 constant USDT_INITIAL_SUPPLY = 1_000_000e6;
    uint256 constant USDT_POOL_SEED = 100_000e6;
    uint256 constant NATIVE_POOL_SEED = 300 ether;

    function run() external returns (address registry_, address usdt_, address escrow_, address asc_) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address monitor = vm.envAddress("MONITOR_ADDRESS");
        address sourceGate = vm.envOr("DOODLE_GATE_SEPOLIA", address(0));

        vm.startBroadcast(pk);

        // ---- implementations + proxies ----
        SeasonRegistry registry = SeasonRegistry(
            address(
                new ERC1967Proxy(address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (deployer)))
            )
        );
        USDT usdt = USDT(address(new ERC1967Proxy(address(new USDT()), abi.encodeCall(USDT.initialize, (deployer)))));
        ArenaEscrow escrow = ArenaEscrow(
            payable(address(
                    new ERC1967Proxy(
                        address(new ArenaEscrow()),
                        abi.encodeCall(ArenaEscrow.initialize, (deployer, address(registry)))
                    )
                ))
        );
        DoodleGateASC asc = DoodleGateASC(
            address(
                new ERC1967Proxy(
                    address(new DoodleGateASC()),
                    abi.encodeCall(DoodleGateASC.initialize, (deployer, address(usdt), address(escrow)))
                )
            )
        );

        // ---- wiring ----
        registry.setEscrow(address(escrow));
        escrow.setAsc(address(asc));
        usdt.setMinter(address(asc), true);

        // Caps: 100 of each, in their own decimals.
        escrow.setMaxStake(address(0), MAX_STAKE_NATIVE);
        escrow.setMaxStake(address(usdt), MAX_STAKE_USDT);

        // Phase 1: a single attestor, the ink-monitor key. Phase 2 swaps in peer quorum by
        // calling setAttestor/setThreshold again - no contract change.
        escrow.setAttestor(monitor, true);
        escrow.setThreshold(1);

        asc.setUsdtPerSourceUnit(vm.envOr("USDT_PER_SOURCE_UNIT", uint256(100e6)));
        asc.setMaxCreditPerQuery(vm.envOr("MAX_CREDIT_PER_QUERY", uint256(1_000e6)));
        if (sourceGate != address(0)) asc.setSourceGate(SEPOLIA_CHAIN_KEY, sourceGate);

        // ---- seed the reward pool so runs can be accepted immediately ----
        usdt.mint(deployer, USDT_INITIAL_SUPPLY);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), USDT_POOL_SEED);
        escrow.fundPool{value: NATIVE_POOL_SEED}(address(0), NATIVE_POOL_SEED);

        vm.stopBroadcast();

        // ---- assertions: a mis-wired deployment must fail loudly, not silently ----
        require(registry.escrow() == address(escrow), "registry not wired to escrow");
        require(escrow.asc() == address(asc), "escrow does not know the ASC");
        require(usdt.isMinter(address(asc)), "ASC cannot mint USDT");
        require(escrow.maxStakeOf(address(0)) == MAX_STAKE_NATIVE, "native cap not set");
        require(escrow.maxStakeOf(address(usdt)) == MAX_STAKE_USDT, "usdt cap not set");
        require(escrow.isAttestor(monitor), "monitor is not an attestor");
        require(escrow.threshold() == 1, "threshold not 1");
        require(escrow.multiplierBpsFor(15) == 30_000, "tiers not initialised");
        require(escrow.poolOf(address(usdt)).free == USDT_POOL_SEED, "usdt pool not seeded");
        require(escrow.poolOf(address(0)).free == NATIVE_POOL_SEED, "native pool not seeded");
        if (sourceGate != address(0)) {
            require(asc.sourceGateOf(SEPOLIA_CHAIN_KEY) == sourceGate, "source gate binding missing");
        }

        console2.log("SEASON_REGISTRY=%s", address(registry));
        console2.log("USDT_TOKEN=%s", address(usdt));
        console2.log("ARENA_ESCROW=%s", address(escrow));
        console2.log("DOODLE_GATE_ASC=%s", address(asc));
        if (sourceGate == address(0)) {
            console2.log("WARNING: DOODLE_GATE_SEPOLIA was empty - the ASC has NO registered");
            console2.log("emitter and will refuse every cross-chain query until setSourceGate.");
        }

        return (address(registry), address(usdt), address(escrow), address(asc));
    }
}
