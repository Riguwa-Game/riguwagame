// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";

import {ASCReadableUpgradeable} from "./ASCReadableUpgradeable.sol";

interface IUSDTMintable {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IArenaPool {
    function fundPool(address token, uint256 amount) external payable;
}

/// @title DoodleGateASC
/// @notice The Attestcoin Smart Contract for Inkstake Arena. Proves that a payment happened on a
///         source chain and credits it on Creditcoin — no oracle, no trusted relayer.
/// @dev Two actions share one source contract, following the protocol's own guidance: a single
///      source-chain emitter with unambiguous, purpose-named events.
///
///      Security rests on two checks, both called out in the Attestcoin docs:
///        1. `receiptStatus == 1`. The precompile proves a transaction was INCLUDED in a real
///           block. It does NOT prove the transaction SUCCEEDED.
///        2. The emitting log address must equal the registered `sourceGate[chainKey]`. Without
///           it, anyone could deploy a look-alike emitter and mint unlimited credit.
contract DoodleGateASC is ASCReadableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error InvalidAction(uint8 action);
    error UnsupportedTxType(uint8 txType);
    error SourceTransactionFailed();
    error NoMatchingEvent();
    error UnknownEmitter(uint64 chainKey, address emitter);
    error CreditTooLarge(uint256 credited, uint256 cap);
    error MalformedEvent();

    enum Action {
        EntryPaid, // 0
        PrizeFunded // 1
    }

    bytes32 public constant ENTRY_PAID_SIGNATURE = keccak256("ArenaEntryPaid(address,bytes32,uint256)");
    bytes32 public constant PRIZE_FUNDED_SIGNATURE = keccak256("PrizePoolFunded(address,uint256)");

    event EntryCredited(address indexed player, bytes32 indexed runRef, uint256 credited, bytes32 indexed queryId);
    event PoolSponsored(address indexed sponsor, uint256 credited, bytes32 indexed queryId);
    event SourceGateSet(uint64 indexed chainKey, address indexed gate);

    /// @custom:storage-location erc7201:inkstake.storage.DoodleGateASC
    struct ASCStorage {
        IUSDTMintable usdt;
        IArenaPool escrow;
        uint256 usdtPerSourceUnit; // USDT (6dp) credited per 1e18 of source-chain value
        uint256 maxCreditPerQuery;
        mapping(uint64 chainKey => address gate) sourceGate;
    }

    bytes32 private constant STORAGE_SLOT = 0x12d06c2cb907555d20e6d5be977c9855812f0706a9bcd821f201f9346d1b8300;

    function _s() private pure returns (ASCStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address usdt_, address escrow_) external initializer {
        __Ownable_init(initialOwner);
        ASCStorage storage $ = _s();
        $.usdt = IUSDTMintable(usdt_);
        $.escrow = IArenaPool(escrow_);
    }

    // ---------------- views and admin ----------------

    function usdt() external view returns (address) {
        return address(_s().usdt);
    }

    function escrow() external view returns (address) {
        return address(_s().escrow);
    }

    function sourceGateOf(uint64 chainKey) external view returns (address) {
        return _s().sourceGate[chainKey];
    }

    function usdtPerSourceUnit() external view returns (uint256) {
        return _s().usdtPerSourceUnit;
    }

    function maxCreditPerQuery() external view returns (uint256) {
        return _s().maxCreditPerQuery;
    }

    /// @notice Bind a source chain to the ONLY contract whose events this ASC will honour.
    function setSourceGate(uint64 chainKey, address gate) external onlyOwner {
        _s().sourceGate[chainKey] = gate;
        emit SourceGateSet(chainKey, gate);
    }

    function setUsdtPerSourceUnit(uint256 rate) external onlyOwner {
        _s().usdtPerSourceUnit = rate;
    }

    function setMaxCreditPerQuery(uint256 cap) external onlyOwner {
        _s().maxCreditPerQuery = cap;
    }

    // ---------------- readability handler ----------------

    function _processAndEmitEvent(uint8 action, uint64 chainKey, bytes32 queryId, bytes memory encodedTransaction)
        internal
        override
    {
        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTxType(txType);

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        // The precompile proves inclusion, not success. This check is mandatory.
        if (receipt.receiptStatus != 1) revert SourceTransactionFailed();

        if (action == uint8(Action.EntryPaid)) {
            _creditEntry(chainKey, queryId, receipt);
        } else if (action == uint8(Action.PrizeFunded)) {
            _sponsorPool(chainKey, queryId, receipt);
        } else {
            revert InvalidAction(action);
        }
    }

    function _creditEntry(uint64 chainKey, bytes32 queryId, EvmV1Decoder.ReceiptFields memory receipt) private {
        EvmV1Decoder.LogEntry[] memory logs = EvmV1Decoder.getLogsByEventSignature(receipt, ENTRY_PAID_SIGNATURE);
        if (logs.length == 0) revert NoMatchingEvent();

        // Policy: only the first matching event in a transaction is honoured.
        EvmV1Decoder.LogEntry memory log = logs[0];
        _requireRegisteredEmitter(chainKey, log.address_);
        if (log.topics.length != 3 || log.data.length != 32) revert MalformedEvent();

        address player = address(uint160(uint256(log.topics[1])));
        bytes32 runRef = log.topics[2];
        uint256 amount = abi.decode(log.data, (uint256));

        uint256 credited = _convert(amount);
        _s().usdt.mint(player, credited);
        emit EntryCredited(player, runRef, credited, queryId);
    }

    function _sponsorPool(uint64 chainKey, bytes32 queryId, EvmV1Decoder.ReceiptFields memory receipt) private {
        EvmV1Decoder.LogEntry[] memory logs = EvmV1Decoder.getLogsByEventSignature(receipt, PRIZE_FUNDED_SIGNATURE);
        if (logs.length == 0) revert NoMatchingEvent();

        EvmV1Decoder.LogEntry memory log = logs[0];
        _requireRegisteredEmitter(chainKey, log.address_);
        if (log.topics.length != 2 || log.data.length != 32) revert MalformedEvent();

        address sponsor = address(uint160(uint256(log.topics[1])));
        uint256 amount = abi.decode(log.data, (uint256));

        ASCStorage storage $ = _s();
        uint256 credited = _convert(amount);
        $.usdt.mint(address(this), credited);
        $.usdt.approve(address($.escrow), credited);
        $.escrow.fundPool(address($.usdt), credited);

        emit PoolSponsored(sponsor, credited, queryId);
    }

    function _requireRegisteredEmitter(uint64 chainKey, address emitter) private view {
        if (_s().sourceGate[chainKey] != emitter || emitter == address(0)) {
            revert UnknownEmitter(chainKey, emitter);
        }
    }

    function _convert(uint256 sourceAmount) private view returns (uint256 credited) {
        ASCStorage storage $ = _s();
        credited = (sourceAmount * $.usdtPerSourceUnit) / 1e18;
        if (credited > $.maxCreditPerQuery) revert CreditTooLarge(credited, $.maxCreditPerQuery);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
