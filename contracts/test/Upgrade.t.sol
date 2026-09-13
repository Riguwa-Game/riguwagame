// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";
import {ArenaEscrowV2, SeasonRegistryV2, USDTV2, DoodleGateASCV2} from "./helpers/V2Mocks.sol";

contract UpgradeTest is Test {
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;
    DoodleGateASC internal asc;

    function setUp() public {
        registry = SeasonRegistry(
            address(new ERC1967Proxy(address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))))
        );
        usdt = USDT(address(new ERC1967Proxy(address(new USDT()), abi.encodeCall(USDT.initialize, (owner)))));
        escrow = ArenaEscrow(
            payable(address(
                    new ERC1967Proxy(
                        address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
                    )
                ))
        );
        asc = DoodleGateASC(
            address(
                new ERC1967Proxy(
                    address(new DoodleGateASC()),
                    abi.encodeCall(DoodleGateASC.initialize, (owner, address(usdt), address(escrow)))
                )
            )
        );

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        vm.stopPrank();
        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);
    }

    // ---------- state survives ----------

    function test_arenaEscrowStateSurvivesAnUpgrade() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: 10 ether}(address(0), 10 ether);

        IArenaEscrow.Run memory before = escrow.runOf(runId);
        IArenaEscrow.Pool memory poolBefore = escrow.poolOf(address(0));

        // Deploy BEFORE the prank: a contract creation in the argument list consumes it.
        address v2 = address(new ArenaEscrowV2());
        vm.prank(owner);
        escrow.upgradeToAndCall(v2, "");

        IArenaEscrow.Run memory afterUpgrade = escrow.runOf(runId);
        assertEq(afterUpgrade.player, before.player);
        assertEq(afterUpgrade.stake, before.stake);
        assertEq(afterUpgrade.reserved, before.reserved);
        assertEq(afterUpgrade.seed, before.seed);
        assertEq(uint8(afterUpgrade.state), uint8(IArenaEscrow.RunState.Active));

        IArenaEscrow.Pool memory poolAfter = escrow.poolOf(address(0));
        assertEq(poolAfter.free, poolBefore.free);
        assertEq(poolAfter.reserved, poolBefore.reserved);
        assertEq(poolAfter.activeStake, poolBefore.activeStake);

        assertEq(ArenaEscrowV2(payable(address(escrow))).version(), "v2");
        assertEq(escrow.owner(), owner, "ownership survives");
        assertEq(escrow.maxStakeOf(address(0)), 100e18, "config survives");
    }

    function test_newV2StorageDoesNotDisturbTheOldState() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: 10 ether}(address(0), 10 ether);

        address impl = address(new ArenaEscrowV2());
        vm.prank(owner);
        escrow.upgradeToAndCall(impl, "");
        ArenaEscrowV2 v2 = ArenaEscrowV2(payable(address(escrow)));
        v2.setNote("hello from v2");

        assertEq(v2.note(), "hello from v2");
        assertEq(v2.runOf(runId).stake, 10 ether, "the run is untouched");
    }

    function test_usdtBalancesSurviveAnUpgrade() public {
        vm.prank(owner);
        usdt.mint(alice, 1_234e6);
        address v2 = address(new USDTV2());
        vm.prank(owner);
        usdt.upgradeToAndCall(v2, "");
        assertEq(usdt.balanceOf(alice), 1_234e6);
        assertEq(usdt.decimals(), 6);
        assertEq(USDTV2(address(usdt)).version(), "v2");
    }

    function test_seasonStatsSurviveAnUpgrade() public {
        vm.prank(address(escrow));
        registry.recordRun(alice, 9, 555, address(0), 1 ether, 0);
        address v2 = address(new SeasonRegistryV2());
        vm.prank(owner);
        registry.upgradeToAndCall(v2, "");
        assertEq(registry.statsOf(1, alice).bestWave, 9);
        assertEq(registry.statsOf(1, alice).bestScore, 555);
    }

    function test_ascConfigSurvivesAnUpgrade() public {
        address gate = makeAddr("gate");
        vm.startPrank(owner);
        asc.setSourceGate(1, gate);
        asc.setUsdtPerSourceUnit(42e6);
        vm.stopPrank();
        address v2 = address(new DoodleGateASCV2());
        vm.prank(owner);
        asc.upgradeToAndCall(v2, "");
        assertEq(asc.sourceGateOf(1), gate, "the emitter binding must survive");
        assertEq(asc.usdtPerSourceUnit(), 42e6);
    }

    // ---------- access control ----------

    function test_revert_strangerCannotUpgradeArenaEscrow() public {
        address v2 = address(new ArenaEscrowV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.upgradeToAndCall(v2, "");
    }

    function test_revert_strangerCannotUpgradeUsdt() public {
        address v2 = address(new USDTV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        usdt.upgradeToAndCall(v2, "");
    }

    function test_revert_strangerCannotUpgradeSeasonRegistry() public {
        address v2 = address(new SeasonRegistryV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        registry.upgradeToAndCall(v2, "");
    }

    function test_revert_strangerCannotUpgradeTheAsc() public {
        address v2 = address(new DoodleGateASCV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        asc.upgradeToAndCall(v2, "");
    }

    // ---------- initialisation ----------

    function test_revert_initializeTwiceOnEveryProxy() public {
        vm.expectRevert();
        escrow.initialize(alice, address(registry));
        vm.expectRevert();
        registry.initialize(alice);
        vm.expectRevert();
        usdt.initialize(alice);
        vm.expectRevert();
        asc.initialize(alice, address(usdt), address(escrow));
    }

    function test_revert_implementationsCannotBeInitialized() public {
        ArenaEscrow e = new ArenaEscrow();
        vm.expectRevert();
        e.initialize(alice, address(registry));

        SeasonRegistry s = new SeasonRegistry();
        vm.expectRevert();
        s.initialize(alice);

        USDT u = new USDT();
        vm.expectRevert();
        u.initialize(alice);

        DoodleGateASC a = new DoodleGateASC();
        vm.expectRevert();
        a.initialize(alice, address(usdt), address(escrow));
    }
}
