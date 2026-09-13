// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IArenaEscrow} from "./interfaces/IArenaEscrow.sol";
import {ISeasonRegistry} from "./interfaces/ISeasonRegistry.sol";

/// @title ArenaEscrow
/// @notice Holds stakes and the reward pool for Inkstake Arena runs.
/// @dev The contract can never owe more than it holds: `startRun` reserves the payout ceiling
///      up front and refuses the run if the pool cannot cover it.
///
///      Only allowlisted tokens can be staked (`setMaxStake`). Fee-on-transfer and rebasing
///      tokens would break the accounting identity and must never be allowlisted.
///
///      ReentrancyGuard is the non-upgradeable one on purpose: OZ 5.7 dropped
///      ReentrancyGuardUpgradeable, and the plain guard is proxy-safe because its check tests
///      `value == ENTERED (2)` while an uninitialised slot reads 0. Its constructor is only a
///      gas optimisation and not running it under a proxy is harmless.
contract ArenaEscrow is
    IArenaEscrow,
    OwnableUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    error RunAlreadyActive();
    error ZeroAmount();
    error BadValue();
    error TokenNotAllowed(address token);
    error StakeAboveCap(uint256 amount, uint256 cap);
    error PoolTooSmall(uint256 free, uint256 needed);
    error NotFunder();
    error InsufficientFree(uint256 free, uint256 requested);
    error BadTiers();

    uint32 public constant BPS_DENOMINATOR = 10_000;

    /// @custom:storage-location erc7201:inkstake.storage.ArenaEscrow
    struct EscrowStorage {
        ISeasonRegistry seasonRegistry;
        address asc; // DoodleGateASC, allowed to fund the pool
        uint32 maxMultiplierBps;
        uint64 runTtl;
        uint256 threshold;
        Tier[] tiers;
        mapping(address account => bool) attestors;
        mapping(address token => uint256) maxStake;
        mapping(address token => Pool) pools;
        mapping(bytes32 runId => Run) runs;
        mapping(address player => bytes32 runId) activeRun;
        mapping(address player => uint256) runNonce;
    }

    bytes32 private constant STORAGE_SLOT =
        0xcf5ea8a7afd0f750bf3fb7589d3874efecbc02abcd883e191bbc203b187f4e00;

    function _s() private pure returns (EscrowStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address seasonRegistry_) external initializer {
        __Ownable_init(initialOwner);
        __EIP712_init("InkstakeArena", "1");

        EscrowStorage storage $ = _s();
        $.seasonRegistry = ISeasonRegistry(seasonRegistry_);
        $.maxMultiplierBps = 30_000;
        $.runTtl = 2 hours;
        $.threshold = 1;

        // Tiers line up with the game's checkpoint rhythm, which unlocks every 5 waves.
        $.tiers.push(Tier({minWave: 5, multiplierBps: 15_000}));
        $.tiers.push(Tier({minWave: 10, multiplierBps: 20_000}));
        $.tiers.push(Tier({minWave: 15, multiplierBps: 30_000}));
    }

    // ---------------- views ----------------

    function runOf(bytes32 runId) external view returns (Run memory) {
        return _s().runs[runId];
    }

    function activeRunOf(address player) external view returns (bytes32) {
        return _s().activeRun[player];
    }

    function poolOf(address token) external view returns (Pool memory) {
        return _s().pools[token];
    }

    function maxStakeOf(address token) external view returns (uint256) {
        return _s().maxStake[token];
    }

    function isAttestor(address account) external view returns (bool) {
        return _s().attestors[account];
    }

    function threshold() external view returns (uint256) {
        return _s().threshold;
    }

    function runTtl() external view returns (uint64) {
        return _s().runTtl;
    }

    function seasonRegistry() external view returns (address) {
        return address(_s().seasonRegistry);
    }

    function asc() external view returns (address) {
        return _s().asc;
    }

    function tiers() external view returns (Tier[] memory) {
        return _s().tiers;
    }

    /// @notice Payout multiplier for a wave, in basis points. Zero means the run was a loss.
    function multiplierBpsFor(uint32 wave) public view returns (uint32 bps) {
        Tier[] storage t = _s().tiers;
        uint256 n = t.length;
        for (uint256 i; i < n; ++i) {
            if (wave >= t[i].minWave) bps = t[i].multiplierBps;
            else break;
        }
    }

    // ---------------- staking ----------------

    /// @notice Stake and begin a run. Reverts unless the pool can cover the payout ceiling.
    function startRun(address token, uint256 amount)
        external
        payable
        nonReentrant
        returns (bytes32 runId)
    {
        EscrowStorage storage $ = _s();

        if ($.activeRun[msg.sender] != bytes32(0)) revert RunAlreadyActive();
        if (amount == 0) revert ZeroAmount();

        uint256 cap = $.maxStake[token];
        if (cap == 0) revert TokenNotAllowed(token);
        if (amount > cap) revert StakeAboveCap(amount, cap);

        _pullFunds(token, amount);

        uint256 ceiling = (amount * $.maxMultiplierBps) / BPS_DENOMINATOR;
        Pool storage p = $.pools[token];
        if (p.free < ceiling) revert PoolTooSmall(p.free, ceiling);
        p.free -= ceiling;
        p.reserved += ceiling;
        p.activeStake += amount;

        uint256 nonce = $.runNonce[msg.sender]++;
        runId = keccak256(abi.encodePacked(address(this), block.chainid, msg.sender, nonce));
        // Committed before play. A validator could nudge blockhash; acceptable for a game seed.
        bytes32 seed = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, nonce));
        uint64 deadline = uint64(block.timestamp) + $.runTtl;

        $.runs[runId] = Run({
            player: msg.sender,
            token: token,
            stake: amount,
            reserved: ceiling,
            seed: seed,
            startedAt: uint64(block.timestamp),
            deadline: deadline,
            state: RunState.Active
        });
        $.activeRun[msg.sender] = runId;

        emit RunStarted(runId, msg.sender, token, amount, seed, deadline);
    }

    /// @notice Add funds to the reward pool. Owner, or the ASC crediting a cross-chain sponsor.
    function fundPool(address token, uint256 amount) external payable {
        EscrowStorage storage $ = _s();
        if (msg.sender != owner() && msg.sender != $.asc) revert NotFunder();
        if (amount == 0) revert ZeroAmount();
        _pullFunds(token, amount);
        $.pools[token].free += amount;
        emit PoolFunded(token, msg.sender, amount);
    }

    /// @notice Withdraw unreserved pool funds. Never touches reservations or live stakes.
    function withdrawFree(address token, address to, uint256 amount) external onlyOwner {
        Pool storage p = _s().pools[token];
        if (amount > p.free) revert InsufficientFree(p.free, amount);
        p.free -= amount;
        _pay(token, to, amount);
    }

    // ---------------- admin ----------------

    function setMaxStake(address token, uint256 cap) external onlyOwner {
        _s().maxStake[token] = cap;
    }

    function setAsc(address asc_) external onlyOwner {
        _s().asc = asc_;
    }

    function setMultiplierTiers(Tier[] calldata newTiers) external onlyOwner {
        EscrowStorage storage $ = _s();
        uint256 n = newTiers.length;
        if (n == 0) revert BadTiers();
        for (uint256 i; i < n; ++i) {
            // A multiplier below 1x would make a "win" pay less than the stake and would
            // underflow the pool accounting in settleRun.
            if (newTiers[i].multiplierBps < BPS_DENOMINATOR) revert BadTiers();
            if (newTiers[i].multiplierBps > $.maxMultiplierBps) revert BadTiers();
            if (i > 0 && newTiers[i].minWave <= newTiers[i - 1].minWave) revert BadTiers();
        }
        delete $.tiers;
        for (uint256 i; i < n; ++i) {
            $.tiers.push(newTiers[i]);
        }
    }

    // ---------------- internals ----------------

    function _pullFunds(address token, uint256 amount) private {
        if (token == address(0)) {
            if (msg.value != amount) revert BadValue();
        } else {
            if (msg.value != 0) revert BadValue();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _pay(address token, address to, uint256 amount) internal {
        if (token == address(0)) Address.sendValue(payable(to), amount);
        else IERC20(token).safeTransfer(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {
        revert NotFunder();
    }
}
