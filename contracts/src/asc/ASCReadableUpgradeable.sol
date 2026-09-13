// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/// @title ASCReadableUpgradeable
/// @notice Proxy-safe base for an Attestcoin Smart Contract using Readability: verify a
///         foreign-chain transaction through the native block-prover precompile, deduplicate by
///         query id, then hand off to app logic.
/// @dev A port of @gluwa/asc-contracts ASCBase with two deliberate changes:
///      1. VERIFIER is a constant, not a constructor-set immutable, so there is no constructor
///         logic under a proxy.
///      2. `_processAndEmitEvent` receives `chainKey`. ASCBase omits it, but a subclass cannot
///         bind a log emitter to a registered source contract without it — and that binding is
///         what stops anyone from deploying a look-alike emitter on the source chain.
abstract contract ASCReadableUpgradeable is Initializable {
    error QueryAlreadyProcessed(bytes32 queryId);
    error ProofVerificationFailed();

    /// @notice The Attestcoin block-prover precompile (`0xFD2` / 4050).
    INativeQueryVerifier internal constant VERIFIER = INativeQueryVerifier(0x0000000000000000000000000000000000000FD2);

    /// @custom:storage-location erc7201:inkstake.storage.ASCReadable
    struct ASCReadableStorage {
        mapping(bytes32 queryId => bool) processed;
    }

    bytes32 private constant STORAGE_SLOT = 0xc93ddaed6853b6750c13e9d657f8d94b1582a34a1c5316222dcd54ccc718c100;

    function _ascStorage() private pure returns (ASCReadableStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    function processedQueries(bytes32 queryId) public view returns (bool) {
        return _ascStorage().processed[queryId];
    }

    /// @notice App-specific handler, invoked only after the proof verifies and dedupes.
    function _processAndEmitEvent(uint8 action, uint64 chainKey, bytes32 queryId, bytes memory encodedTransaction)
        internal
        virtual;

    /// @notice Verify inclusion and continuity, enforce one-time processing, then run app logic.
    function execute(
        uint8 action,
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) external returns (bool) {
        bytes32 queryId = _computeQueryId(chainKey, blockHeight, merkleRoot, siblings);

        ASCReadableStorage storage $ = _ascStorage();
        if ($.processed[queryId]) revert QueryAlreadyProcessed(queryId);

        INativeQueryVerifier.MerkleProof memory merkleProof =
            INativeQueryVerifier.MerkleProof({root: merkleRoot, siblings: siblings});
        INativeQueryVerifier.ContinuityProof memory continuityProof =
            INativeQueryVerifier.ContinuityProof({lowerEndpointDigest: lowerEndpointDigest, roots: continuityRoots});

        bool verified = VERIFIER.verifyAndEmit(chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof);
        if (!verified) revert ProofVerificationFailed();

        $.processed[queryId] = true;

        _processAndEmitEvent(action, chainKey, queryId, encodedTransaction);
        return true;
    }

    function _computeQueryId(
        uint64 chainKey,
        uint64 blockHeight,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings
    ) internal view returns (bytes32) {
        INativeQueryVerifier.MerkleProof memory merkleProof =
            INativeQueryVerifier.MerkleProof({root: merkleRoot, siblings: siblings});
        uint64 txIndex = VERIFIER.calculateTxIndex(merkleProof);
        return keccak256(abi.encodePacked(chainKey, blockHeight, txIndex));
    }
}
