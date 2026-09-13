// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IArenaEscrow {
    enum RunState {
        None,
        Active,
        Settled,
        Abandoned
    }

    struct Run {
        address player;
        address token; // address(0) == native tCTC
        uint256 stake;
        uint256 reserved; // payout ceiling locked at startRun
        bytes32 seed;
        uint64 startedAt;
        uint64 deadline;
        RunState state;
    }

    /// @dev EIP-712 signed payload. Attestors sign exactly this.
    struct RunResult {
        bytes32 runId;
        address player;
        uint32 waveReached;
        uint64 score;
        uint64 endedAt;
    }

    /// @dev Payout schedule. `minWave` is an inclusive lower bound; tiers ascend.
    struct Tier {
        uint32 minWave;
        uint32 multiplierBps; // 15_000 == 1.5x
    }

    /// @dev Invariant: token balance == free + reserved + activeStake
    struct Pool {
        uint256 free;
        uint256 reserved;
        uint256 activeStake;
    }

    event RunStarted(
        bytes32 indexed runId,
        address indexed player,
        address indexed token,
        uint256 stake,
        bytes32 seed,
        uint64 deadline
    );
    event RunSettled(
        bytes32 indexed runId, address indexed player, uint32 waveReached, uint64 score, uint256 payout
    );
    event RunAbandoned(bytes32 indexed runId, address indexed player, uint256 refunded);
    event PoolFunded(address indexed token, address indexed from, uint256 amount);
}
