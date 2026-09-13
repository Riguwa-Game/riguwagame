// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {ISeasonRegistry} from "../src/interfaces/ISeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {SignerLib} from "./helpers/SignerLib.sol";
import {Reenterer} from "./helpers/Reenterer.sol";

contract ArenaEscrowSettleTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    uint256 internal monitorPk;
    address internal monitor;
    uint256 internal strangerPk;
    address internal stranger;
    uint256 internal peerPk;
    address internal peer;

    function setUp() public {
        (monitor, monitorPk) = makeAddrAndKey("monitor");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        (peer, peerPk) = makeAddrAndKey("peer");

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

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        escrow.setMaxStake(address(usdt), 100e6);
        escrow.setAttestor(monitor, true);
        escrow.setThreshold(1);
        usdt.mint(owner, 1_000_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 100_000e6);
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

    function _result(bytes32 runId, uint32 wave, uint64 score) internal view returns (IArenaEscrow.RunResult memory) {
        return IArenaEscrow.RunResult({
            runId: runId, player: alice, waveReached: wave, score: score, endedAt: uint64(block.timestamp)
        });
    }

    function _sign(uint256 pk, IArenaEscrow.RunResult memory r) internal view returns (bytes memory) {
        return SignerLib.sign(pk, escrow.hashRunResult(r));
    }

    // ---------- positive ----------

    function test_winAtWaveFivePaysOneAndAHalfTimes() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 5, 4200);
        uint256 before = alice.balance;

        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));

        assertEq(alice.balance - before, 15 ether, "1.5x of a 10 ether stake");
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Settled));
        assertEq(escrow.activeRunOf(alice), bytes32(0), "the active-run slot must be cleared");
    }

    function test_winAtWaveFifteenPaysTheCap() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 15, 99_000);
        uint256 before = alice.balance;
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
        assertEq(alice.balance - before, 30 ether, "3x is the ceiling");
    }

    function test_lossAbsorbsTheStakeIntoThePool() public {
        IArenaEscrow.Pool memory p0 = escrow.poolOf(address(0));
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 4, 300);
        uint256 before = alice.balance;

        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));

        assertEq(alice.balance, before, "a loss pays nothing");
        IArenaEscrow.Pool memory p1 = escrow.poolOf(address(0));
        assertEq(p1.free, p0.free + 10 ether, "the stake joins the pool");
        assertEq(p1.reserved, 0);
        assertEq(p1.activeStake, 0);
    }

    function test_settlementRecordsTheRunInTheSeasonRegistry() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 12, 7777);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));

        ISeasonRegistry.PlayerStats memory s = registry.statsOf(1, alice);
        assertEq(s.runs, 1);
        assertEq(s.wins, 1);
        assertEq(s.bestWave, 12);
        assertEq(s.bestScore, 7777);
        assertEq(s.totalWon, 20 ether);
    }

    function test_theAccountingIdentityHoldsAfterSettlement() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    function test_phaseTwoShape_twoOfThreeAttestorsSuffice() public {
        vm.startPrank(owner);
        escrow.setAttestor(peer, true);
        escrow.setThreshold(2);
        vm.stopPrank();

        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 5);
        escrow.settleRun(r, SignerLib.two(_sign(monitorPk, r), _sign(peerPk, r)));
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Settled));
    }

    // ---------- edge ----------

    function test_waveFourVersusWaveFiveIsTheLossWinBoundary() public {
        bytes32 a = _start(1 ether);
        IArenaEscrow.RunResult memory ra = _result(a, 4, 1);
        uint256 b0 = alice.balance;
        escrow.settleRun(ra, SignerLib.one(_sign(monitorPk, ra)));
        assertEq(alice.balance, b0, "wave 4 pays nothing");

        bytes32 b = _start(1 ether);
        IArenaEscrow.RunResult memory rb = _result(b, 5, 1);
        uint256 b1 = alice.balance;
        escrow.settleRun(rb, SignerLib.one(_sign(monitorPk, rb)));
        assertEq(alice.balance - b1, 1.5 ether, "wave 5 pays 1.5x");
    }

    function test_settlementExactlyAtTheDeadlineIsAllowed() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
    }

    function test_anyoneMaySubmitAValidlySignedResult() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        vm.prank(makeAddr("randomRelayer"));
        escrow.settleRun(r, sigs);
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Settled));
    }

    function test_reentrancyDuringPayoutIsBlockedAndTheBalanceIsCorrect() public {
        Reenterer attacker = new Reenterer(escrow);
        vm.deal(address(attacker), 10 ether);
        bytes32 runId = attacker.start{value: 1 ether}(1 ether);

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId, player: address(attacker), waveReached: 15, score: 1, endedAt: uint64(block.timestamp)
        });
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        attacker.arm(r, sigs);

        uint256 before = address(attacker).balance;
        escrow.settleRun(r, sigs);

        assertTrue(attacker.reentered(), "the callback must have fired");
        assertTrue(attacker.reentryReverted(), "the re-entrant call must revert");
        assertEq(address(attacker).balance - before, 3 ether, "paid exactly once");
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    // ---------- negative ----------

    function test_revert_signatureFromANonAttestor() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(strangerPk, r));
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.NotAttestor.selector, stranger));
        escrow.settleRun(r, sigs);
    }

    function test_revert_belowThreshold() public {
        vm.prank(owner);
        escrow.setThreshold(2);
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        // sign BEFORE expectRevert: _sign calls escrow.hashRunResult, which would otherwise be
        // the call expectRevert latches onto.
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.ThresholdNotMet.selector, 1, 2));
        escrow.settleRun(r, sigs);
    }

    function test_revert_theSameSignerCountedTwice() public {
        vm.prank(owner);
        escrow.setThreshold(2);
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes memory sig = _sign(monitorPk, r);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.DuplicateSigner.selector, monitor));
        escrow.settleRun(r, SignerLib.two(sig, sig));
    }

    function test_revert_signatureOverADifferentRunId() public {
        bytes32 runA = _start(1 ether);
        IArenaEscrow.RunResult memory ra = _result(runA, 15, 1);
        bytes memory sigForA = _sign(monitorPk, ra);
        escrow.settleRun(ra, SignerLib.one(sigForA));

        bytes32 runB = _start(1 ether);
        IArenaEscrow.RunResult memory rb = _result(runB, 15, 1);
        bytes[] memory sigsB = SignerLib.one(sigForA);
        vm.expectRevert();
        escrow.settleRun(rb, sigsB);
    }

    function test_revert_signatureFromADifferentChainIdDomain() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);

        bytes32 wrongDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("InkstakeArena")),
                keccak256(bytes("1")),
                uint256(999999),
                address(escrow)
            )
        );
        bytes32 structHash =
            keccak256(abi.encode(escrow.RUN_RESULT_TYPEHASH(), r.runId, r.player, r.waveReached, r.score, r.endedAt));
        bytes32 foreign = keccak256(abi.encodePacked("\x19\x01", wrongDomain, structHash));

        vm.expectRevert();
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, foreign)));
    }

    function test_revert_settlingTwice() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        escrow.settleRun(r, sigs);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.settleRun(r, sigs);
    }

    function test_revert_playerFieldDoesNotMatchTheRun() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId, player: stranger, waveReached: 15, score: 1, endedAt: uint64(block.timestamp)
        });
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        vm.expectRevert(ArenaEscrow.PlayerMismatch.selector);
        escrow.settleRun(r, sigs);
    }

    function test_revert_settlingAfterTheDeadline() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        vm.expectRevert(ArenaEscrow.RunExpired.selector);
        escrow.settleRun(r, sigs);
    }

    function test_revert_unknownRunId() public {
        IArenaEscrow.RunResult memory r = _result(keccak256("nope"), 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.settleRun(r, sigs);
    }

    function test_revert_malformedSignatureBytes() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(hex"deadbeef");
        vm.expectRevert();
        escrow.settleRun(r, sigs);
    }

    function test_revert_malleableSignature() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(monitorPk, escrow.hashRunResult(r));

        uint256 N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 sFlipped = bytes32(N - uint256(ss));
        uint8 vFlipped = v == 27 ? 28 : 27;

        vm.expectRevert();
        escrow.settleRun(r, SignerLib.one(abi.encodePacked(rr, sFlipped, vFlipped)));
    }

    function test_revert_emptySignatureArray() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory none = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.ThresholdNotMet.selector, 0, 1));
        escrow.settleRun(r, none);
    }
}
