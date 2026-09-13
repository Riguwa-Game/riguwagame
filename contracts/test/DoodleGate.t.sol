// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DoodleGate} from "../src/sepolia/DoodleGate.sol";

contract DoodleGateTest is Test {
    DoodleGate internal gate;
    address internal owner = makeAddr("owner");
    address internal player = makeAddr("player");
    address internal sponsor = makeAddr("sponsor");
    bytes32 constant RUN_REF = keccak256("run-ref");

    event ArenaEntryPaid(address indexed player, bytes32 indexed runRef, uint256 amount);
    event PrizePoolFunded(address indexed sponsor, uint256 amount);

    function setUp() public {
        gate = new DoodleGate(owner);
        vm.deal(player, 10 ether);
        vm.deal(sponsor, 10 ether);
    }

    // ---------- positive ----------

    function test_payEntryEmitsTheEventAndHoldsTheFunds() public {
        vm.expectEmit(true, true, false, true, address(gate));
        emit ArenaEntryPaid(player, RUN_REF, 1 ether);
        vm.prank(player);
        gate.payEntry{value: 1 ether}(RUN_REF);
        assertEq(address(gate).balance, 1 ether);
    }

    function test_fundPrizeEmitsTheEvent() public {
        vm.expectEmit(true, false, false, true, address(gate));
        emit PrizePoolFunded(sponsor, 2 ether);
        vm.prank(sponsor);
        gate.fundPrize{value: 2 ether}();
        assertEq(address(gate).balance, 2 ether);
    }

    function test_ownerCanWithdraw() public {
        vm.prank(player);
        gate.payEntry{value: 1 ether}(RUN_REF);
        uint256 before = owner.balance;
        vm.prank(owner);
        gate.withdraw(owner);
        assertEq(owner.balance - before, 1 ether);
        assertEq(address(gate).balance, 0);
    }

    // ---------- edge ----------

    function test_theSamePlayerCanPayForSeveralRuns() public {
        vm.startPrank(player);
        gate.payEntry{value: 1 ether}(keccak256("a"));
        gate.payEntry{value: 1 ether}(keccak256("b"));
        vm.stopPrank();
        assertEq(address(gate).balance, 2 ether);
    }

    // ---------- negative ----------

    function test_revert_payEntryWithNoValue() public {
        vm.prank(player);
        vm.expectRevert(DoodleGate.ZeroValue.selector);
        gate.payEntry(RUN_REF);
    }

    function test_revert_fundPrizeWithNoValue() public {
        vm.prank(sponsor);
        vm.expectRevert(DoodleGate.ZeroValue.selector);
        gate.fundPrize();
    }

    function test_revert_strangerCannotWithdraw() public {
        vm.prank(player);
        gate.payEntry{value: 1 ether}(RUN_REF);
        vm.prank(player);
        vm.expectRevert();
        gate.withdraw(player);
    }

    function test_revert_plainTransfersAreRejected() public {
        vm.prank(player);
        (bool ok,) = address(gate).call{value: 1 ether}("");
        assertFalse(ok, "a bare transfer emits no event and must be refused");
    }
}
