// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ISeasonRegistry {
    struct PlayerStats {
        uint32 bestWave;
        uint64 bestScore;
        uint32 runs;
        uint32 wins;
        uint256 totalStaked;
        uint256 totalWon;
    }

    function recordRun(
        address player,
        uint32 waveReached,
        uint64 score,
        address token,
        uint256 staked,
        uint256 won
    ) external;

    function currentSeason() external view returns (uint64);

    function statsOf(uint64 season, address player) external view returns (PlayerStats memory);
}
