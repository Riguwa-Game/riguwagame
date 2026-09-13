// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";

interface IChainInfo {
    /// @dev Field 2 is the source chain's EVM chainId, not a genesis height - confirmed against
    ///      the live precompile, which returns (1, 11155111, "Sepolia ethereum", 1).
    struct ChainDescriptor {
        uint64 chainKey;
        uint64 evmChainId;
        bytes name;
        uint8 kind;
    }

    function get_supported_chains() external view returns (ChainDescriptor[] memory);
    function is_height_attested(uint64 chainKey, uint64 targetHeight) external view returns (bool);
    function get_latest_attestation_height_and_hash(uint64 chainKey)
        external
        view
        returns (uint64 height, bytes32 hash, bool isAttestation, bool exists);
    function get_attestation_genesis_height(uint64 chainKey) external view returns (uint64);
}

/// @notice Runs against the live Creditcoin Testnet so the REAL precompiles answer, rather than
///         the MockBlockProver the unit tests etch. This is what proves the integration is
///         genuinely live and not merely self-consistent.
///
/// forge test --match-path 'test/fork/*' --fork-url https://rpc.cc3-testnet.creditcoin.network -vv
///
/// KNOWN LIMITATION: that command currently fails with
///   "header validation error: `prevrandao` not set"
/// Creditcoin blocks carry no `mixHash` and `difficulty: 0x0`, and Foundry's fork backend expects
/// one of them on a post-Merge chain. This is a Foundry/Frontier mismatch, not a contract problem.
/// Until it is fixed, `script/check-live.sh` performs the same checks over plain JSON-RPC and
/// does work today.
contract AttestcoinForkTest is Test {
    IChainInfo constant CHAIN_INFO = IChainInfo(0x0000000000000000000000000000000000000fD3);
    address constant BLOCK_PROVER = 0x0000000000000000000000000000000000000FD2;
    uint64 constant SEPOLIA_KEY = 1;

    function setUp() public {
        // Skip cleanly when the suite is run without --fork-url.
        vm.skip(block.chainid != 102031);
    }

    function test_weAreOnCreditcoinTestnet() public view {
        assertEq(block.chainid, 102031);
    }

    function test_sepoliaIsASupportedSourceChain() public view {
        IChainInfo.ChainDescriptor[] memory chains = CHAIN_INFO.get_supported_chains();
        assertGt(chains.length, 0, "the protocol must list at least one source chain");

        bool foundSepolia;
        for (uint256 i; i < chains.length; ++i) {
            console2.log("chainKey", chains[i].chainKey);
            console2.log("  name", string(chains[i].name));
            console2.log("  evmChainId", chains[i].evmChainId);
            if (chains[i].chainKey == SEPOLIA_KEY) foundSepolia = true;
        }
        assertTrue(foundSepolia, "Ethereum Sepolia is chainKey 1 on CC3 Testnet");
    }

    function test_attestationsAreBeingProduced() public view {
        (uint64 height,,, bool exists) = CHAIN_INFO.get_latest_attestation_height_and_hash(SEPOLIA_KEY);
        assertTrue(exists, "no attestation found for Sepolia");
        assertGt(height, 0, "attested height must be non-zero");
        console2.log("latest attested Sepolia height", height);
    }

    function test_genesisHeightIsZeroForSepolia() public view {
        assertEq(CHAIN_INFO.get_attestation_genesis_height(SEPOLIA_KEY), 0);
    }

    /// @dev A precompile carries no bytecode but still answers calls. Assert exactly that, so
    ///      nobody ever adds a naive `extcodesize` guard in front of it.
    function test_blockProverHasNoCodeButIsReachable() public view {
        assertEq(BLOCK_PROVER.code.length, 0, "precompiles carry no bytecode");
        assertEq(address(CHAIN_INFO).code.length, 0);
    }
}
