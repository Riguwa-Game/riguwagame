// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ArenaEscrow} from "../../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../../src/interfaces/IArenaEscrow.sol";

/// @notice A "player" that tries to re-enter the escrow while being paid.
contract Reenterer {
    ArenaEscrow public escrow;
    IArenaEscrow.RunResult internal stored;
    bytes[] internal storedSigs;
    bool public reentered;
    bool public reentryReverted;

    constructor(ArenaEscrow e) {
        escrow = e;
    }

    function start(uint256 amount) external payable returns (bytes32) {
        return escrow.startRun{value: amount}(address(0), amount);
    }

    function arm(IArenaEscrow.RunResult calldata r, bytes[] calldata sigs) external {
        stored = r;
        delete storedSigs;
        for (uint256 i; i < sigs.length; ++i) {
            storedSigs.push(sigs[i]);
        }
    }

    receive() external payable {
        if (reentered) return;
        reentered = true;
        try escrow.settleRun(stored, storedSigs) {
            reentryReverted = false;
        } catch {
            reentryReverted = true;
        }
    }
}
