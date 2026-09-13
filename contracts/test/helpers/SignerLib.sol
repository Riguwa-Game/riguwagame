// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vm} from "forge-std/Vm.sol";

library SignerLib {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function one(bytes memory a) internal pure returns (bytes[] memory out) {
        out = new bytes[](1);
        out[0] = a;
    }

    function two(bytes memory a, bytes memory b) internal pure returns (bytes[] memory out) {
        out = new bytes[](2);
        out[0] = a;
        out[1] = b;
    }
}
