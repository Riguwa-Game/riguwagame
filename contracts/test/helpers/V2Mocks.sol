// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ArenaEscrow} from "../../src/ArenaEscrow.sol";
import {SeasonRegistry} from "../../src/SeasonRegistry.sol";
import {USDT} from "../../src/USDT.sol";
import {DoodleGateASC} from "../../src/asc/DoodleGateASC.sol";

/// @dev V2s add a variable in their own namespaced slot. ERC-7201 keeps namespaces apart, so
///      nothing that existed before can be displaced.
contract ArenaEscrowV2 is ArenaEscrow {
    /// @custom:storage-location erc7201:inkstake.storage.ArenaEscrowV2
    struct V2Storage {
        string note;
    }

    bytes32 private constant V2_SLOT = 0x508726c531209bf6e5f3c8b91742dd7155652fc3483b0639aa9a036235ecc7d1; // keccak256("inkstake.storage.ArenaEscrowV2.test")

    function setNote(string calldata n) external {
        V2Storage storage $;
        assembly {
            $.slot := V2_SLOT
        }
        $.note = n;
    }

    function note() external view returns (string memory) {
        V2Storage storage $;
        assembly {
            $.slot := V2_SLOT
        }
        return $.note;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract SeasonRegistryV2 is SeasonRegistry {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract USDTV2 is USDT {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract DoodleGateASCV2 is DoodleGateASC {
    function version() external pure returns (string memory) {
        return "v2";
    }
}
