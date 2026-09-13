// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {ISeasonRegistry} from "../src/interfaces/ISeasonRegistry.sol";

contract SeasonRegistryTest is Test {
    SeasonRegistry internal reg;
    address internal owner = makeAddr("owner");
    address internal escrow = makeAddr("escrow");
    address internal alice = makeAddr("alice");
    address internal token = makeAddr("token");

    function setUp() public {
        SeasonRegistry impl = new SeasonRegistry();
        reg = SeasonRegistry(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(SeasonRegistry.initialize, (owner))))
        );
        vm.prank(owner);
        reg.setEscrow(escrow);
    }

    function _record(uint32 wave, uint64 score, uint256 staked, uint256 won) internal {
        vm.prank(escrow);
        reg.recordRun(alice, wave, score, token, staked, won);
    }

    // ---------- positive ----------

    function test_startsAtSeasonOne() public view {
        assertEq(reg.currentSeason(), 1);
    }

    function test_recordsARun() public {
        _record(7, 1234, 10e18, 15e18);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.runs, 1);
        assertEq(s.wins, 1, "a payout above zero counts as a win");
        assertEq(s.bestWave, 7);
        assertEq(s.bestScore, 1234);
        assertEq(s.totalStaked, 10e18);
        assertEq(s.totalWon, 15e18);
    }

    function test_aLossIncrementsRunsButNotWins() public {
        _record(3, 400, 5e18, 0);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.runs, 1);
        assertEq(s.wins, 0);
    }

    // ---------- edge ----------

    function test_bestWaveAndBestScoreOnlyEverImprove() public {
        _record(12, 9000, 1e18, 2e18);
        _record(4, 100, 1e18, 0);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.bestWave, 12);
        assertEq(s.bestScore, 9000);
        assertEq(s.runs, 2);
    }

    function test_bestScoreImprovesEvenWhenTheWaveIsLower() public {
        _record(10, 100, 1e18, 0);
        _record(9, 5000, 1e18, 0);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.bestWave, 10);
        assertEq(s.bestScore, 5000);
    }

    function test_newSeasonStartsFromCleanStats() public {
        _record(12, 9000, 1e18, 2e18);
        vm.prank(owner);
        uint64 next = reg.startNewSeason();
        assertEq(next, 2);
        assertEq(reg.currentSeason(), 2);

        ISeasonRegistry.PlayerStats memory fresh = reg.statsOf(2, alice);
        assertEq(fresh.runs, 0);
        assertEq(fresh.bestWave, 0);

        ISeasonRegistry.PlayerStats memory old = reg.statsOf(1, alice);
        assertEq(old.bestWave, 12, "history must survive a season rollover");
    }

    function test_waveZeroIsRecordable() public {
        _record(0, 0, 1e18, 0);
        assertEq(reg.statsOf(1, alice).runs, 1);
    }

    function test_totalsAccumulateAcrossRuns() public {
        _record(6, 10, 1e18, 1.5e18);
        _record(11, 20, 2e18, 4e18);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.totalStaked, 3e18);
        assertEq(s.totalWon, 5.5e18);
        assertEq(s.wins, 2);
    }

    // ---------- negative ----------

    function test_revert_onlyEscrowCanRecord() public {
        vm.prank(alice);
        vm.expectRevert(SeasonRegistry.NotEscrow.selector);
        reg.recordRun(alice, 5, 1, token, 1, 1);
    }

    function test_revert_ownerCannotRecordEither() public {
        vm.prank(owner);
        vm.expectRevert(SeasonRegistry.NotEscrow.selector);
        reg.recordRun(alice, 5, 1, token, 1, 1);
    }

    function test_revert_strangerCannotSetEscrow() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        reg.setEscrow(alice);
    }

    function test_revert_strangerCannotStartASeason() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        reg.startNewSeason();
    }

    function test_revert_initializeTwice() public {
        vm.expectRevert();
        reg.initialize(alice);
    }
}
