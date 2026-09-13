// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";
import {ASCReadableUpgradeable} from "../src/asc/ASCReadableUpgradeable.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {MockBlockProver} from "./helpers/MockBlockProver.sol";
import {TxFixture} from "./helpers/TxFixture.sol";

contract DoodleGateASCTest is Test {
    address constant PRECOMPILE = 0x0000000000000000000000000000000000000FD2;
    uint64 constant SEPOLIA_KEY = 1; // Attestcoin chainKey, not 11155111

    DoodleGateASC internal asc;
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;

    address internal owner = makeAddr("owner");
    address internal player = makeAddr("player");
    address internal sponsor = makeAddr("sponsor");
    address internal sourceGate = makeAddr("sourceGate");
    address internal impostorGate = makeAddr("impostorGate");

    bytes32 constant RUN_REF = keccak256("run-ref-1");

    function setUp() public {
        MockBlockProver prover = new MockBlockProver();
        vm.etch(PRECOMPILE, address(prover).code);
        MockBlockProver(PRECOMPILE).mockSet(true, 3, false);

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
        escrow.setAsc(address(asc));
        escrow.setMaxStake(address(usdt), 100e6);
        usdt.setMinter(address(asc), true);
        asc.setSourceGate(SEPOLIA_KEY, sourceGate);
        asc.setUsdtPerSourceUnit(100e6);
        asc.setMaxCreditPerQuery(1_000e6);
        vm.stopPrank();
    }

    function _siblings() internal pure returns (INativeQueryVerifier.MerkleProofEntry[] memory s) {
        s = new INativeQueryVerifier.MerkleProofEntry[](1);
        s[0] = INativeQueryVerifier.MerkleProofEntry({hash: keccak256("sib"), isLeft: true});
    }

    function _roots() internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = keccak256("root");
    }

    function _entryTx(address emitter, uint8 status, uint256 amount) internal view returns (bytes memory) {
        bytes32[] memory topics =
            TxFixture.topics3(asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), RUN_REF);
        return TxFixture.encode(2, player, emitter, status, TxFixture.oneLog(emitter, topics, abi.encode(amount)));
    }

    function _prizeTx(address emitter, uint8 status, uint256 amount) internal view returns (bytes memory) {
        bytes32[] memory topics = TxFixture.topics2(asc.PRIZE_FUNDED_SIGNATURE(), bytes32(uint256(uint160(sponsor))));
        return TxFixture.encode(2, sponsor, emitter, status, TxFixture.oneLog(emitter, topics, abi.encode(amount)));
    }

    function _exec(uint8 action, bytes memory encodedTx, uint64 height) internal returns (bool) {
        return asc.execute(
            action, SEPOLIA_KEY, height, encodedTx, keccak256("merkleRoot"), _siblings(), keccak256("lower"), _roots()
        );
    }

    // ---------- positive ----------

    function test_entryPaidMintsCreditToThePlayer() public {
        _exec(0, _entryTx(sourceGate, 1, 2e18), 100);
        assertEq(usdt.balanceOf(player), 200e6, "2 units x 100 USDT");
    }

    function test_prizeFundedTopsUpTheRewardPool() public {
        _exec(1, _prizeTx(sourceGate, 1, 5e18), 101);
        assertEq(escrow.poolOf(address(usdt)).free, 500e6);
        assertEq(usdt.balanceOf(address(escrow)), 500e6);
    }

    function test_queryIsMarkedProcessed() public {
        _exec(0, _entryTx(sourceGate, 1, 1e18), 102);
        bytes32 queryId = keccak256(abi.encodePacked(SEPOLIA_KEY, uint64(102), uint64(3)));
        assertTrue(asc.processedQueries(queryId));
    }

    function test_signaturesMatchTheSourceContract() public view {
        assertEq(asc.ENTRY_PAID_SIGNATURE(), keccak256("ArenaEntryPaid(address,bytes32,uint256)"));
        assertEq(asc.PRIZE_FUNDED_SIGNATURE(), keccak256("PrizePoolFunded(address,uint256)"));
    }

    function test_creditedPlayerCanImmediatelyStake() public {
        _exec(0, _entryTx(sourceGate, 1, 1e18), 103);
        vm.startPrank(owner);
        usdt.mint(owner, 10_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 10_000e6);
        vm.stopPrank();

        vm.startPrank(player);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.startRun(address(usdt), 100e6); // never held tCTC
        vm.stopPrank();
        assertTrue(escrow.activeRunOf(player) != bytes32(0));
    }

    // ---------- edge ----------

    function test_onlyTheMatchingEventIsPickedOutOfABusyTransaction() public {
        TxFixture.Log[] memory logs = new TxFixture.Log[](3);
        logs[0] = TxFixture.Log({
            address_: makeAddr("someToken"),
            topics: TxFixture.topics2(keccak256("Transfer(address,address,uint256)"), bytes32(0)),
            data: abi.encode(uint256(999))
        });
        logs[1] = TxFixture.Log({
            address_: sourceGate,
            topics: TxFixture.topics3(asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), RUN_REF),
            data: abi.encode(uint256(1e18))
        });
        logs[2] = TxFixture.Log({
            address_: makeAddr("noise"),
            topics: TxFixture.topics2(keccak256("Approval(address,address,uint256)"), bytes32(0)),
            data: abi.encode(uint256(1))
        });
        _exec(0, TxFixture.encode(2, player, sourceGate, 1, logs), 104);
        assertEq(usdt.balanceOf(player), 100e6);
    }

    function test_differentChainKeysRegisterIndependently() public {
        address otherGate = makeAddr("otherGate");
        vm.prank(owner);
        asc.setSourceGate(3, otherGate); // Ethereum mainnet is chainKey 3
        assertEq(asc.sourceGateOf(SEPOLIA_KEY), sourceGate);
        assertEq(asc.sourceGateOf(3), otherGate);
    }

    function test_sameHeightDifferentTxIndexAreDistinctQueries() public {
        _exec(0, _entryTx(sourceGate, 1, 1e18), 105);
        MockBlockProver(PRECOMPILE).mockSet(true, 4, false);
        _exec(0, _entryTx(sourceGate, 1, 1e18), 105);
        assertEq(usdt.balanceOf(player), 200e6, "both were credited");
    }

    // ---------- negative ----------

    function test_revert_replayOfTheSameQuery() public {
        bytes memory encodedTx = _entryTx(sourceGate, 1, 1e18);
        _exec(0, encodedTx, 106);
        bytes32 queryId = keccak256(abi.encodePacked(SEPOLIA_KEY, uint64(106), uint64(3)));
        vm.expectRevert(abi.encodeWithSelector(ASCReadableUpgradeable.QueryAlreadyProcessed.selector, queryId));
        _exec(0, encodedTx, 106);
    }

    /// The precompile proves INCLUSION, not SUCCESS. A reverted payment must never mint.
    function test_revert_transactionThatFailedOnTheSourceChain() public {
        bytes memory encodedTx = _entryTx(sourceGate, 0, 1e18);
        vm.expectRevert(DoodleGateASC.SourceTransactionFailed.selector);
        _exec(0, encodedTx, 107);
    }

    /// THE most important test in this repository. Without the emitter binding, anyone can
    /// deploy a look-alike contract on Sepolia and mint themselves unlimited credit.
    function test_revert_eventFromAnUnregisteredEmitter() public {
        bytes memory encodedTx = _entryTx(impostorGate, 1, 1e18);
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.UnknownEmitter.selector, SEPOLIA_KEY, impostorGate));
        _exec(0, encodedTx, 108);
    }

    function test_revert_unregisteredChainKey() public {
        bytes memory encodedTx = _entryTx(sourceGate, 1, 1e18);
        INativeQueryVerifier.MerkleProofEntry[] memory sib = _siblings();
        bytes32[] memory rts = _roots();
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.UnknownEmitter.selector, uint64(99), sourceGate));
        asc.execute(0, 99, 109, encodedTx, keccak256("merkleRoot"), sib, keccak256("lower"), rts);
    }

    function test_revert_unknownAction() public {
        bytes memory encodedTx = _entryTx(sourceGate, 1, 1e18);
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.InvalidAction.selector, uint8(7)));
        _exec(7, encodedTx, 110);
    }

    function test_revert_noMatchingEventInTheTransaction() public {
        TxFixture.Log[] memory logs = new TxFixture.Log[](1);
        logs[0] = TxFixture.Log({
            address_: sourceGate,
            topics: TxFixture.topics2(keccak256("Transfer(address,address,uint256)"), bytes32(0)),
            data: abi.encode(uint256(1))
        });
        bytes memory encodedTx = TxFixture.encode(2, player, sourceGate, 1, logs);
        vm.expectRevert(DoodleGateASC.NoMatchingEvent.selector);
        _exec(0, encodedTx, 111);
    }

    function test_revert_whenTheProofDoesNotVerify() public {
        MockBlockProver(PRECOMPILE).mockSet(false, 3, false);
        bytes memory encodedTx = _entryTx(sourceGate, 1, 1e18);
        vm.expectRevert(ASCReadableUpgradeable.ProofVerificationFailed.selector);
        _exec(0, encodedTx, 112);
    }

    function test_revert_creditAboveThePerQueryCap() public {
        bytes memory encodedTx = _entryTx(sourceGate, 1, 20e18);
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.CreditTooLarge.selector, 2_000e6, 1_000e6));
        _exec(0, encodedTx, 113);
    }

    function test_revert_strangerCannotSetSourceGate() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        asc.setSourceGate(SEPOLIA_KEY, impostorGate);
    }

    function test_revert_strangerCannotChangeTheRate() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        asc.setUsdtPerSourceUnit(1);
    }
}
