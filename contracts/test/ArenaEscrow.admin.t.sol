// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {SignerLib} from "./helpers/SignerLib.sol";

contract ArenaEscrowAdminTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    uint256 internal monitorPk;
    address internal monitor;

    function setUp() public {
        (monitor, monitorPk) = makeAddrAndKey("monitor");
        registry = SeasonRegistry(
            address(new ERC1967Proxy(address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))))
        );
        escrow = ArenaEscrow(
            payable(address(
                    new ERC1967Proxy(
                        address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
                    )
                ))
        );
        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        escrow.setAttestor(monitor, true);
        vm.stopPrank();
        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);
        vm.deal(alice, 1_000 ether);
    }

    function _start(uint256 amount) internal returns (bytes32) {
        vm.prank(alice);
        return escrow.startRun{value: amount}(address(0), amount);
    }

    function _res(bytes32 runId, uint32 wave) internal view returns (IArenaEscrow.RunResult memory) {
        return IArenaEscrow.RunResult({
            runId: runId, player: alice, waveReached: wave, score: 1, endedAt: uint64(block.timestamp)
        });
    }

    // ---------- abandon: positive ----------

    function test_abandonAfterTheDeadlineReturnsTheExactStake() public {
        IArenaEscrow.Pool memory p0 = escrow.poolOf(address(0));
        bytes32 runId = _start(10 ether);
        uint256 before = alice.balance;

        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);

        assertEq(alice.balance - before, 10 ether, "stake returned in full");
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Abandoned));
        assertEq(escrow.activeRunOf(alice), bytes32(0));

        IArenaEscrow.Pool memory p1 = escrow.poolOf(address(0));
        assertEq(p1.free, p0.free, "the pool is made whole");
        assertEq(p1.reserved, 0);
        assertEq(p1.activeStake, 0);
        assertEq(address(escrow).balance, p1.free + p1.reserved + p1.activeStake);
    }

    function test_anyoneMayTriggerAnAbandon() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        vm.prank(makeAddr("goodSamaritan"));
        escrow.abandonRun(runId);
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Abandoned));
    }

    function test_theSamePlayerCanStartAgainAfterAbandoning() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);
        bytes32 second = _start(1 ether);
        assertTrue(second != runId);
    }

    // ---------- abandon: negative ----------

    function test_revert_abandonBeforeTheDeadline() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline);
        vm.expectRevert(ArenaEscrow.RunNotExpired.selector);
        escrow.abandonRun(runId);
    }

    function test_revert_abandonTwice() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.abandonRun(runId);
    }

    function test_revert_settleAfterAbandon() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);

        IArenaEscrow.RunResult memory r = _res(runId, 15);
        bytes[] memory sigs = SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r)));
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.settleRun(r, sigs);
    }

    function test_revert_abandonAfterSettle() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _res(runId, 15);
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r))));
        vm.warp(block.timestamp + 3 hours);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.abandonRun(runId);
    }

    // ---------- admin access control ----------

    function test_revert_strangerCannotSetAttestor() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.setAttestor(alice, true);
    }

    function test_revert_strangerCannotSetThreshold() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.setThreshold(5);
    }

    function test_revert_strangerCannotSetMaxStake() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.setMaxStake(address(0), 1);
    }

    function test_revert_strangerCannotWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.withdrawFree(address(0), alice, 1);
    }

    function test_revert_strangerCannotFundPool() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.NotFunder.selector);
        escrow.fundPool{value: 1 ether}(address(0), 1 ether);
    }

    function test_ascCanFundPool() public {
        address ascAddr = makeAddr("asc");
        vm.prank(owner);
        escrow.setAsc(ascAddr);
        vm.deal(ascAddr, 5 ether);
        vm.prank(ascAddr);
        escrow.fundPool{value: 5 ether}(address(0), 5 ether);
        assertEq(escrow.poolOf(address(0)).free, 1_005 ether);
    }

    function test_revert_thresholdCannotBeZero() public {
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setThreshold(0);
    }

    function test_ownerCanRotateTheAttestorKey() public {
        address fresh = makeAddr("freshMonitor");
        vm.startPrank(owner);
        escrow.setAttestor(monitor, false);
        escrow.setAttestor(fresh, true);
        vm.stopPrank();
        assertFalse(escrow.isAttestor(monitor));
        assertTrue(escrow.isAttestor(fresh));
    }

    // ---------- tier validation ----------

    function test_revert_tiersBelowOneTimesAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](1);
        t[0] = IArenaEscrow.Tier({minWave: 5, multiplierBps: 9_000});
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_revert_tiersAboveTheMaximumAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](1);
        t[0] = IArenaEscrow.Tier({minWave: 5, multiplierBps: 30_001});
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_revert_nonMonotonicTiersAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](2);
        t[0] = IArenaEscrow.Tier({minWave: 10, multiplierBps: 20_000});
        t[1] = IArenaEscrow.Tier({minWave: 5, multiplierBps: 15_000});
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_revert_emptyTiersAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](0);
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_ownerCanReplaceTheTierSchedule() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](2);
        t[0] = IArenaEscrow.Tier({minWave: 3, multiplierBps: 12_000});
        t[1] = IArenaEscrow.Tier({minWave: 20, multiplierBps: 25_000});
        vm.prank(owner);
        escrow.setMultiplierTiers(t);
        assertEq(escrow.multiplierBpsFor(2), 0);
        assertEq(escrow.multiplierBpsFor(3), 12_000);
        assertEq(escrow.multiplierBpsFor(19), 12_000);
        assertEq(escrow.multiplierBpsFor(20), 25_000);
    }

    // ---------- a real-game scenario ----------

    function test_scenario_monitorGoesDownMidRunAndThePlayerIsMadeWhole() public {
        uint256 before = alice.balance;
        bytes32 runId = _start(25 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        escrow.abandonRun(runId);
        assertEq(alice.balance, before, "the player is exactly where they started");
    }
}
