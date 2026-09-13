// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";
import {MockBlockProver} from "./helpers/MockBlockProver.sol";
import {TxFixture} from "./helpers/TxFixture.sol";

/// @notice Exercises the accessors and the malformed-input branches that the behavioural suites
///         do not reach. These are real code paths, not metric padding: a malformed event is
///         exactly what a buggy or hostile source contract would produce.
contract CoverageTest is Test {
    address constant PRECOMPILE = 0x0000000000000000000000000000000000000FD2;
    uint64 constant SEPOLIA_KEY = 1;

    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;
    DoodleGateASC internal asc;

    address internal owner = makeAddr("owner");
    address internal player = makeAddr("player");
    address internal sourceGate = makeAddr("sourceGate");

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
        usdt.setMinter(address(asc), true);
        asc.setSourceGate(SEPOLIA_KEY, sourceGate);
        asc.setUsdtPerSourceUnit(100e6);
        asc.setMaxCreditPerQuery(1_000e6);
        vm.stopPrank();
    }

    // ---------- accessors ----------

    function test_escrowAccessorsReportConfiguration() public {
        assertEq(escrow.seasonRegistry(), address(registry));
        assertEq(escrow.asc(), address(asc));
        assertEq(escrow.runTtl(), 2 hours);
        assertEq(escrow.threshold(), 1);
        assertFalse(escrow.isAttestor(player));

        IArenaEscrow.Tier[] memory t = escrow.tiers();
        assertEq(t.length, 3);
        assertEq(t[0].minWave, 5);
        assertEq(t[0].multiplierBps, 15_000);
        assertEq(t[2].minWave, 15);
        assertEq(t[2].multiplierBps, 30_000);

        vm.startPrank(owner);
        escrow.setRunTtl(45 minutes);
        escrow.setSeasonRegistry(address(0xBEEF));
        vm.stopPrank();
        assertEq(escrow.runTtl(), 45 minutes);
        assertEq(escrow.seasonRegistry(), address(0xBEEF));
    }

    function test_otherAccessors() public view {
        assertEq(registry.escrow(), address(escrow));
        assertFalse(usdt.isMinter(player));
        assertTrue(usdt.isMinter(address(asc)));
        assertEq(usdt.lastFaucet(player), 0);
        assertEq(asc.usdt(), address(usdt));
        assertEq(asc.escrow(), address(escrow));
        assertEq(asc.maxCreditPerQuery(), 1_000e6);
    }

    // ---------- malformed source events ----------

    function _siblings() internal pure returns (INativeQueryVerifier.MerkleProofEntry[] memory s) {
        s = new INativeQueryVerifier.MerkleProofEntry[](1);
        s[0] = INativeQueryVerifier.MerkleProofEntry({hash: keccak256("sib"), isLeft: true});
    }

    function _roots() internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = keccak256("root");
    }

    function _exec(uint8 action, bytes memory encodedTx, uint64 height) internal {
        asc.execute(
            action, SEPOLIA_KEY, height, encodedTx, keccak256("merkleRoot"), _siblings(), keccak256("lower"), _roots()
        );
    }

    function test_revert_entryEventWithTooFewTopics() public {
        // right signature, but the indexed runRef is missing
        bytes32[] memory topics = TxFixture.topics2(asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))));
        bytes memory encodedTx =
            TxFixture.encode(2, player, sourceGate, 1, TxFixture.oneLog(sourceGate, topics, abi.encode(uint256(1e18))));
        vm.expectRevert(DoodleGateASC.MalformedEvent.selector);
        _exec(0, encodedTx, 200);
    }

    function test_revert_entryEventWithWrongDataLength() public {
        bytes32[] memory topics =
            TxFixture.topics3(asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), keccak256("ref"));
        bytes memory encodedTx =
            TxFixture.encode(2, player, sourceGate, 1, TxFixture.oneLog(sourceGate, topics, hex"c0ffee"));
        vm.expectRevert(DoodleGateASC.MalformedEvent.selector);
        _exec(0, encodedTx, 201);
    }

    function test_revert_prizeEventWithTooManyTopics() public {
        bytes32[] memory topics =
            TxFixture.topics3(asc.PRIZE_FUNDED_SIGNATURE(), bytes32(uint256(uint160(player))), keccak256("extra"));
        bytes memory encodedTx =
            TxFixture.encode(2, player, sourceGate, 1, TxFixture.oneLog(sourceGate, topics, abi.encode(uint256(1e18))));
        vm.expectRevert(DoodleGateASC.MalformedEvent.selector);
        _exec(1, encodedTx, 202);
    }

    function test_revert_prizeEventWithWrongDataLength() public {
        bytes32[] memory topics = TxFixture.topics2(asc.PRIZE_FUNDED_SIGNATURE(), bytes32(uint256(uint160(player))));
        bytes memory encodedTx =
            TxFixture.encode(2, player, sourceGate, 1, TxFixture.oneLog(sourceGate, topics, hex"01"));
        vm.expectRevert(DoodleGateASC.MalformedEvent.selector);
        _exec(1, encodedTx, 203);
    }

    function test_revert_prizeEventFromAnUnregisteredEmitter() public {
        address impostor = makeAddr("impostor");
        bytes32[] memory topics = TxFixture.topics2(asc.PRIZE_FUNDED_SIGNATURE(), bytes32(uint256(uint160(player))));
        bytes memory encodedTx =
            TxFixture.encode(2, player, impostor, 1, TxFixture.oneLog(impostor, topics, abi.encode(uint256(1e18))));
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.UnknownEmitter.selector, SEPOLIA_KEY, impostor));
        _exec(1, encodedTx, 204);
    }

    function test_revert_unsupportedTransactionType() public {
        bytes32[] memory topics =
            TxFixture.topics3(asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), keccak256("ref"));
        // type 5 does not exist in the EVM encoding the decoder understands
        bytes memory encodedTx =
            TxFixture.encode(5, player, sourceGate, 1, TxFixture.oneLog(sourceGate, topics, abi.encode(uint256(1e18))));
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.UnsupportedTxType.selector, uint8(5)));
        _exec(0, encodedTx, 205);
    }

    function test_revert_sourceGateOfZeroIsNeverAcceptedAsAnEmitter() public {
        // chainKey 7 was never registered, so sourceGate is address(0) and the log emitter is too
        bytes32[] memory topics =
            TxFixture.topics3(asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), keccak256("ref"));
        bytes memory encodedTx =
            TxFixture.encode(2, player, address(0), 1, TxFixture.oneLog(address(0), topics, abi.encode(uint256(1e18))));
        INativeQueryVerifier.MerkleProofEntry[] memory sib = _siblings();
        bytes32[] memory rts = _roots();
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.UnknownEmitter.selector, uint64(7), address(0)));
        asc.execute(0, 7, 206, encodedTx, keccak256("merkleRoot"), sib, keccak256("lower"), rts);
    }
}
