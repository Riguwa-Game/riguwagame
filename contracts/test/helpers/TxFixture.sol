// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Builds `encodedTransaction` bytes in the exact layout EvmV1Decoder expects, so unit
///         tests need no live Sepolia transaction. The fork test uses real bytes.
/// @dev The encoding is abi.encode(uint8 txType, bytes[] chunks). For types 0-2 there are exactly
///      three chunks and the receipt is chunks[2]; chunks[1] holds type-specific fields that
///      decodeReceiptFields and decodeCommonTxFields never read, so it can be empty.
library TxFixture {
    struct Log {
        address address_;
        bytes32[] topics;
        bytes data;
    }

    function encode(uint8 txType, address from, address to, uint8 status, Log[] memory logs)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory common = abi.encode(uint64(1), uint64(21000), from, false, to, uint256(0), bytes(""));
        bytes memory receipt = abi.encode(status, uint64(21000), logs, bytes(""));

        bytes[] memory chunks = new bytes[](3);
        chunks[0] = common;
        chunks[1] = bytes("");
        chunks[2] = receipt;

        return abi.encode(txType, chunks);
    }

    function oneLog(address emitter, bytes32[] memory topics, bytes memory data)
        internal
        pure
        returns (Log[] memory out)
    {
        out = new Log[](1);
        out[0] = Log({address_: emitter, topics: topics, data: data});
    }

    function topics2(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory t) {
        t = new bytes32[](2);
        t[0] = a;
        t[1] = b;
    }

    function topics3(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory t) {
        t = new bytes32[](3);
        t[0] = a;
        t[1] = b;
        t[2] = c;
    }
}
