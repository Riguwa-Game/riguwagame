// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/// @notice Proves the Attestcoin package resolves, and pins the transaction encoding layout the
///         fixtures in test/helpers/TxFixture.sol depend on.
contract ImportsTest is Test {
    function test_precompileAddressIsCorrect() public pure {
        assertEq(address(NativeQueryVerifierLib.getVerifier()), 0x0000000000000000000000000000000000000FD2);
    }

    function test_decoderReadsTheTypeByte() public pure {
        bytes[] memory chunks = new bytes[](3);
        bytes memory encoded = abi.encode(uint8(2), chunks);
        assertEq(EvmV1Decoder.getTransactionType(encoded), 2);
        assertTrue(EvmV1Decoder.isValidTransactionType(2));
        assertFalse(EvmV1Decoder.isValidTransactionType(5));
    }

    function test_creditcoinChainIdIsRecognised() public pure {
        assertTrue(NativeQueryVerifierLib.isCreditcoinChainId(102031));
        assertFalse(NativeQueryVerifierLib.isCreditcoinChainId(1));
    }
}
