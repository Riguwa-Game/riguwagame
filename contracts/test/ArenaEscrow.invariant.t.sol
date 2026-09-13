// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {SignerLib} from "./helpers/SignerLib.sol";

/// @notice Drives the escrow with randomised calls. Reverts are allowed and expected — the point
///         is that no sequence of SUCCESSFUL calls can break the accounting identity.
contract EscrowHandler is Test {
    ArenaEscrow public escrow;
    uint256 internal monitorPk;
    address[] public players;
    bytes32[] public openRuns;

    constructor(ArenaEscrow e, uint256 pk, address[] memory p) {
        escrow = e;
        monitorPk = pk;
        players = p;
    }

    function startRun(uint256 playerSeed, uint256 amount) external {
        address player = players[playerSeed % players.length];
        amount = bound(amount, 1, 100e18);
        if (escrow.activeRunOf(player) != bytes32(0)) return;
        if (escrow.poolOf(address(0)).free < amount * 3) return;

        vm.deal(player, player.balance + amount);
        vm.prank(player);
        try escrow.startRun{value: amount}(address(0), amount) returns (bytes32 runId) {
            openRuns.push(runId);
        } catch {}
    }

    function settleRun(uint256 runSeed, uint32 wave) external {
        if (openRuns.length == 0) return;
        bytes32 runId = openRuns[runSeed % openRuns.length];
        IArenaEscrow.Run memory run = escrow.runOf(runId);
        if (run.state != IArenaEscrow.RunState.Active) return;
        if (block.timestamp > run.deadline) return;

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId,
            player: run.player,
            waveReached: uint32(bound(wave, 0, 40)),
            score: 1,
            endedAt: uint64(block.timestamp)
        });
        try escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r)))) {} catch {}
    }

    function abandonRun(uint256 runSeed) external {
        if (openRuns.length == 0) return;
        try escrow.abandonRun(openRuns[runSeed % openRuns.length]) {} catch {}
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 3 hours));
    }
}

contract ArenaEscrowInvariantTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    EscrowHandler internal handler;
    address internal owner = makeAddr("owner");

    function setUp() public {
        (address monitor, uint256 monitorPk) = makeAddrAndKey("monitor");

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
        escrow.setThreshold(1);
        vm.stopPrank();

        vm.deal(owner, 100_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 50_000 ether}(address(0), 50_000 ether);

        address[] memory players = new address[](4);
        players[0] = makeAddr("p0");
        players[1] = makeAddr("p1");
        players[2] = makeAddr("p2");
        players[3] = makeAddr("p3");

        handler = new EscrowHandler(escrow, monitorPk, players);
        targetContract(address(handler));
    }

    /// @notice The contract always holds exactly what it says it holds.
    function invariant_balanceEqualsPoolAccounting() public view {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    /// @notice Reservations always cover a full payout of every live run.
    function invariant_reservedCoversEveryLiveRun() public view {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertGe(p.reserved, p.activeStake * 3);
    }
}

contract ArenaEscrowFuzzTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    uint256 internal monitorPk;

    function setUp() public {
        address monitor;
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
        vm.deal(owner, 1_000_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 500_000 ether}(address(0), 500_000 ether);
    }

    function testFuzz_payoutNeverExceedsTheReservation(uint256 amount, uint32 wave) public {
        amount = bound(amount, 1, 100e18);
        wave = uint32(bound(wave, 0, 100));

        vm.deal(alice, amount);
        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: amount}(address(0), amount);
        uint256 reserved = escrow.runOf(runId).reserved;

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId, player: alice, waveReached: wave, score: 1, endedAt: uint64(block.timestamp)
        });
        uint256 before = alice.balance;
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r))));

        assertLe(alice.balance - before, reserved, "a payout can never exceed its reservation");
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    function testFuzz_abandonAlwaysReturnsExactlyTheStake(uint256 amount) public {
        amount = bound(amount, 1, 100e18);
        vm.deal(alice, amount);
        uint256 before = alice.balance;

        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: amount}(address(0), amount);
        vm.warp(block.timestamp + 3 hours);
        escrow.abandonRun(runId);

        assertEq(alice.balance, before, "the player ends exactly where they started");
    }
}
