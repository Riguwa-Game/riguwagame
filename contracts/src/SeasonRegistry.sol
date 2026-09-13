// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ISeasonRegistry} from "./interfaces/ISeasonRegistry.sol";

/// @title SeasonRegistry
/// @notice Per-season, per-player record of runs: best wave, best score, totals.
/// @dev Elo is intentionally absent. Elo is a pairwise PvP rating and is meaningless against
///      bots; it belongs to Phase 2, when there are real opponents.
contract SeasonRegistry is ISeasonRegistry, OwnableUpgradeable, UUPSUpgradeable {
    error NotEscrow();

    event RunRecorded(
        uint64 indexed season,
        address indexed player,
        uint32 waveReached,
        uint64 score,
        address token,
        uint256 staked,
        uint256 won
    );
    event SeasonStarted(uint64 indexed season, uint64 startedAt);
    event EscrowSet(address indexed escrow);

    /// @custom:storage-location erc7201:inkstake.storage.SeasonRegistry
    struct RegistryStorage {
        address escrow;
        uint64 season;
        mapping(uint64 season => mapping(address player => PlayerStats)) stats;
    }

    bytes32 private constant STORAGE_SLOT = 0x7a4a5c417275a8e784c1b2fa5f44d304cfe537c32066064710d669f7da8bf400;

    function _s() private pure returns (RegistryStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        _s().season = 1;
        emit SeasonStarted(1, uint64(block.timestamp));
    }

    modifier onlyEscrow() {
        if (msg.sender != _s().escrow) revert NotEscrow();
        _;
    }

    function escrow() external view returns (address) {
        return _s().escrow;
    }

    function currentSeason() external view returns (uint64) {
        return _s().season;
    }

    function statsOf(uint64 season, address player) external view returns (PlayerStats memory) {
        return _s().stats[season][player];
    }

    function setEscrow(address newEscrow) external onlyOwner {
        _s().escrow = newEscrow;
        emit EscrowSet(newEscrow);
    }

    function startNewSeason() external onlyOwner returns (uint64) {
        RegistryStorage storage $ = _s();
        uint64 next = $.season + 1;
        $.season = next;
        emit SeasonStarted(next, uint64(block.timestamp));
        return next;
    }

    function recordRun(address player, uint32 waveReached, uint64 score, address token, uint256 staked, uint256 won)
        external
        onlyEscrow
    {
        RegistryStorage storage $ = _s();
        uint64 season = $.season;
        PlayerStats storage p = $.stats[season][player];

        p.runs += 1;
        if (won > 0) p.wins += 1;
        if (waveReached > p.bestWave) p.bestWave = waveReached;
        if (score > p.bestScore) p.bestScore = score;
        p.totalStaked += staked;
        p.totalWon += won;

        emit RunRecorded(season, player, waveReached, score, token, staked, won);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
