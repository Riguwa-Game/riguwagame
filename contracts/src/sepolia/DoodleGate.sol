// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title DoodleGate
/// @notice Source-chain entry point for Inkstake Arena, deployed on Ethereum Sepolia.
/// @dev Deliberately minimal. Attestcoin guidance is to keep source-chain logic as small as
///      possible and let it exist mainly to emit unambiguous, purpose-named events that an
///      Attestcoin Smart Contract on Creditcoin can prove and act on.
///
///      NOT upgradeable, on purpose: a mutable source contract would undermine the emitter
///      binding that secures the bridge.
///
///      Funds accumulate here. Attestcoin Writability (Creditcoin to other chains) is still
///      under audit and unavailable on testnet; when it ships, two-way settlement replaces
///      `withdraw`.
contract DoodleGate is Ownable {
    error ZeroValue();

    event ArenaEntryPaid(address indexed player, bytes32 indexed runRef, uint256 amount);
    event PrizePoolFunded(address indexed sponsor, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Pay for a run on Creditcoin from this chain.
    /// @param runRef A client-generated reference tying this payment to an intended run.
    function payEntry(bytes32 runRef) external payable {
        if (msg.value == 0) revert ZeroValue();
        emit ArenaEntryPaid(msg.sender, runRef, msg.value);
    }

    /// @notice Sponsor the Creditcoin reward pool from this chain.
    function fundPrize() external payable {
        if (msg.value == 0) revert ZeroValue();
        emit PrizePoolFunded(msg.sender, msg.value);
    }

    function withdraw(address to) external onlyOwner {
        Address.sendValue(payable(to), address(this).balance);
    }
}
