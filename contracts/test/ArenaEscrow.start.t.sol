// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";

contract ArenaEscrowStartTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant MAX_NATIVE = 100e18;
    uint256 constant MAX_USDT = 100e6;

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

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), MAX_NATIVE);
        escrow.setMaxStake(address(usdt), MAX_USDT);
        usdt.mint(owner, 1_000_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 100_000e6);
        vm.stopPrank();

        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);

        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        vm.prank(owner);
        usdt.mint(alice, 10_000e6);
        vm.prank(alice);
        usdt.approve(address(escrow), type(uint256).max);
    }

    // ---------- positive ----------

    function test_startNativeRunLocksTheStakeAndReservesThePayoutCeiling() public {
        IArenaEscrow.Pool memory before = escrow.poolOf(address(0));

        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: 10 ether}(address(0), 10 ether);

        IArenaEscrow.Run memory r = escrow.runOf(runId);
        assertEq(r.player, alice);
        assertEq(r.token, address(0));
        assertEq(r.stake, 10 ether);
        assertEq(r.reserved, 30 ether, "ceiling is 3x the stake");
        assertTrue(r.seed != bytes32(0), "a seed must be issued");
        assertEq(uint8(r.state), uint8(IArenaEscrow.RunState.Active));
        assertEq(escrow.activeRunOf(alice), runId);

        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(p.free, before.free - 30 ether);
        assertEq(p.reserved, before.reserved + 30 ether);
        assertEq(p.activeStake, before.activeStake + 10 ether);
    }

    function test_startUsdtRun() public {
        vm.prank(alice);
        bytes32 runId = escrow.startRun(address(usdt), 50e6);
        IArenaEscrow.Run memory r = escrow.runOf(runId);
        assertEq(r.token, address(usdt));
        assertEq(r.stake, 50e6);
        assertEq(r.reserved, 150e6);
        assertEq(usdt.balanceOf(address(escrow)), 100_000e6 + 50e6);
    }

    function test_theAccountingIdentityHoldsAfterAStart() public {
        vm.prank(alice);
        escrow.startRun{value: 7 ether}(address(0), 7 ether);
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    function test_twoPlayersCanRunConcurrently() public {
        vm.prank(alice);
        bytes32 a = escrow.startRun{value: 1 ether}(address(0), 1 ether);
        vm.prank(bob);
        bytes32 b = escrow.startRun{value: 2 ether}(address(0), 2 ether);
        assertTrue(a != b, "run ids must be distinct");
    }

    // ---------- edge ----------

    function test_stakeExactlyAtTheCapIsAccepted() public {
        vm.prank(alice);
        escrow.startRun{value: MAX_NATIVE}(address(0), MAX_NATIVE);
        assertEq(escrow.runOf(escrow.activeRunOf(alice)).stake, MAX_NATIVE);
    }

    function test_capsAreIndependentPerTokenDecimals() public view {
        assertEq(escrow.maxStakeOf(address(0)), 100e18);
        assertEq(escrow.maxStakeOf(address(usdt)), 100e6);
    }

    function test_multiplierTierBoundaries() public view {
        assertEq(escrow.multiplierBpsFor(0), 0);
        assertEq(escrow.multiplierBpsFor(4), 0, "wave 4 is still a loss");
        assertEq(escrow.multiplierBpsFor(5), 15_000, "wave 5 is the first winning tier");
        assertEq(escrow.multiplierBpsFor(9), 15_000);
        assertEq(escrow.multiplierBpsFor(10), 20_000);
        assertEq(escrow.multiplierBpsFor(14), 20_000);
        assertEq(escrow.multiplierBpsFor(15), 30_000);
        assertEq(escrow.multiplierBpsFor(9999), 30_000, "capped at the maximum tier");
    }

    function test_poolExactlyCoveringTheCeilingIsAccepted() public {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        vm.prank(owner);
        escrow.withdrawFree(address(0), owner, p.free - 3 ether);

        vm.prank(alice);
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
        assertEq(escrow.poolOf(address(0)).free, 0);
    }

    // ---------- negative ----------

    function test_revert_secondRunWhileOneIsActive() public {
        vm.startPrank(alice);
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
        vm.expectRevert(ArenaEscrow.RunAlreadyActive.selector);
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
        vm.stopPrank();
    }

    function test_revert_stakeAboveTheCap() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.StakeAboveCap.selector, MAX_NATIVE + 1, MAX_NATIVE));
        escrow.startRun{value: MAX_NATIVE + 1}(address(0), MAX_NATIVE + 1);
    }

    function test_revert_zeroStake() public {
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.ZeroAmount.selector);
        escrow.startRun(address(0), 0);
    }

    function test_revert_nativeValueMismatch() public {
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.BadValue.selector);
        escrow.startRun{value: 1 ether}(address(0), 2 ether);
    }

    function test_revert_sendingValueAlongsideAnErc20Stake() public {
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.BadValue.selector);
        escrow.startRun{value: 1 ether}(address(usdt), 10e6);
    }

    function test_revert_unallowlistedToken() public {
        address stranger = makeAddr("randomToken");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.TokenNotAllowed.selector, stranger));
        escrow.startRun(stranger, 1);
    }

    function test_revert_erc20StakeWithoutApproval() public {
        vm.prank(owner);
        usdt.mint(bob, 100e6);
        vm.prank(bob);
        vm.expectRevert();
        escrow.startRun(address(usdt), 10e6);
    }

    function test_revert_poolCannotCoverThePayoutCeiling() public {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        vm.prank(owner);
        escrow.withdrawFree(address(0), owner, p.free);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.PoolTooSmall.selector, 0, 3 ether));
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
    }

    function test_revert_withdrawFreeCannotTouchReservedFunds() public {
        vm.prank(alice);
        escrow.startRun{value: 10 ether}(address(0), 10 ether);
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));

        vm.prank(owner);
        vm.expectRevert();
        escrow.withdrawFree(address(0), owner, p.free + 1);
    }

    function test_revert_bareTransfersAreRejected() public {
        vm.prank(alice);
        (bool ok,) = address(escrow).call{value: 1 ether}("");
        assertFalse(ok, "value must arrive through fundPool or startRun");
    }
}
