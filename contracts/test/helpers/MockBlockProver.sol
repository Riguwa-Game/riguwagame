// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/// @notice Stand-in for the Creditcoin block-prover precompile, which has no bytecode on a local
///         EVM. Etch this at 0x…0FD2 with `vm.etch`, then call `mockSet` on that address.
///         vm.etch copies runtime code but leaves storage empty, which is why the config is
///         written through a setter rather than a constructor.
contract MockBlockProver {
    bool public shouldVerify;
    uint64 public nextTxIndex;
    bool public shouldRevertOnVerify;

    function mockSet(bool verify, uint64 txIndex, bool doRevert) external {
        shouldVerify = verify;
        nextTxIndex = txIndex;
        shouldRevertOnVerify = doRevert;
    }

    function verifyAndEmit(
        uint64,
        uint64,
        bytes calldata,
        INativeQueryVerifier.MerkleProof calldata,
        INativeQueryVerifier.ContinuityProof calldata
    ) external view returns (bool) {
        require(!shouldRevertOnVerify, "MockBlockProver: forced revert");
        return shouldVerify;
    }

    function calculateTxIndex(INativeQueryVerifier.MerkleProof calldata) external view returns (uint64) {
        return nextTxIndex;
    }
}
