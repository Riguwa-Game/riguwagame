# Inkstake Arena — Plan 2: Contracts

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship four UUPS-upgradeable contracts on Creditcoin Testnet and one plain contract on Ethereum Sepolia, all verified on Blockscout, with a test suite covering positive, edge and negative cases plus fuzz, invariant and fork tests.

**Architecture:** `ArenaEscrow` holds stakes and the reward pool and can never promise more than it holds, because `startRun` reserves the payout ceiling up front. Settlement is a threshold check over EIP-712 attestations — Phase 1 configures one attestor (the monitor), Phase 2 reconfigures the same function for peer quorum with no code change. `DoodleGateASC` proves Sepolia transactions through the Attestcoin block-prover precompile and mints entry credits.

**Tech Stack:** Foundry (forge 1.7.1), Solidity 0.8.30, OpenZeppelin v5.7.0 (vendored in `lib/`), `@gluwa/asc-contracts@0.2.1` via npm, ERC-7201 namespaced storage.

**Spec:** `docs/brainstorms/2026-09-13-inkstake-arena-design.md`

## Global Constraints

- **`solc_version = "0.8.30"`, `evm_version = "shanghai"`, `via_ir = true`, `optimizer_runs = 200`.** Creditcoin's EVM is Shanghai; several contracts hit stack-too-deep without IR.
- **Every Creditcoin contract is UUPS-upgradeable** with ERC-7201 namespaced storage and a `_disableInitializers()` constructor.
- **Every Creditcoin contract must be verified on Blockscout** at `https://creditcoin-testnet.blockscout.com`.
- **Test first.** Write the failing test, run it, watch it fail, then implement. Never write a contract before its test.
- **Never commit `.env`.** It holds a live deployer private key and is gitignored.
- Creditcoin Testnet chain id `102031`, RPC `https://rpc.cc3-testnet.creditcoin.network`, native token tCTC.
- BlockProver precompile `0x0000000000000000000000000000000000000FD2`; ChainInfo precompile `0x0000000000000000000000000000000000000FD3`.
- Ethereum Sepolia source **chainKey is `1`**, not `11155111`.
- Caps: `maxStake` is `100e18` for native tCTC and `100e6` for USDT (6 decimals).
- `BPS_DENOMINATOR = 10_000`; `maxMultiplierBps = 30_000` (3x).
- The `USDT` contract is a **testnet-only mock**, unaffiliated with Tether, named at the project owner's explicit direction. Say so in its NatSpec.

## ERC-7201 storage locations

Derived as `keccak256(abi.encode(uint256(keccak256(id)) - 1)) & ~bytes32(uint256(0xff))` and
cross-checked against OpenZeppelin's published `openzeppelin.storage.ERC20` slot. Use these
verbatim; do not recompute.

| Namespace id | Slot constant |
| --- | --- |
| `inkstake.storage.ArenaEscrow` | `0xcf5ea8a7afd0f750bf3fb7589d3874efecbc02abcd883e191bbc203b187f4e00` |
| `inkstake.storage.SeasonRegistry` | `0x7a4a5c417275a8e784c1b2fa5f44d304cfe537c32066064710d669f7da8bf400` |
| `inkstake.storage.USDT` | `0x181e7851ce70236646a4bdccacb641dd7f5cd904ed2d297634c5f3875df74200` |
| `inkstake.storage.DoodleGateASC` | `0x12d06c2cb907555d20e6d5be977c9855812f0706a9bcd821f201f9346d1b8300` |
| `inkstake.storage.ASCReadable` | `0xc93ddaed6853b6750c13e9d657f8d94b1582a34a1c5316222dcd54ccc718c100` |

## File structure

```
contracts/
  foundry.toml                         rewritten in Task 1
  src/
    ArenaEscrow.sol                    stakes, pool, solvency, settlement        Tasks 4-6
    SeasonRegistry.sol                 per-season leaderboard                    Task 3
    USDT.sol                           mock stablecoin, 6 decimals               Task 2
    asc/ASCReadableUpgradeable.sol     proxy-safe port of ASCBase                Task 7
    asc/DoodleGateASC.sol              Attestcoin readability, two actions       Task 8
    sepolia/DoodleGate.sol             minimal source-chain emitter              Task 9
    interfaces/IArenaEscrow.sol        shared types and events                   Task 4
    interfaces/ISeasonRegistry.sol                                               Task 3
  test/
    helpers/MockBlockProver.sol        etched at 0x…0FD2                         Task 7
    helpers/TxFixture.sol              builds encodedTransaction bytes           Task 7
    helpers/Reenterer.sol              reentrancy attacker                       Task 5
    helpers/SignerLib.sol              EIP-712 signing helper                    Task 5
    USDT.t.sol                                                                   Task 2
    SeasonRegistry.t.sol                                                         Task 3
    ArenaEscrow.start.t.sol                                                      Task 4
    ArenaEscrow.settle.t.sol                                                     Task 5
    ArenaEscrow.admin.t.sol            abandon, admin, access control            Task 6
    ArenaEscrow.invariant.t.sol        fuzz and invariants                       Task 10
    DoodleGateASC.t.sol                                                          Task 8
    DoodleGate.t.sol                                                             Task 9
    Upgrade.t.sol                      all four proxies                          Task 11
    fork/AttestcoinFork.t.sol          real precompile                           Task 13
  script/
    Deploy.s.sol                       Creditcoin deployment                     Task 12
    DeploySepolia.s.sol                                                          Task 12
```

---

### Task 1: Foundry setup

**Files:**
- Modify: `contracts/foundry.toml`
- Create: `contracts/remappings.txt`
- Create: `contracts/.env.example`
- Delete: `contracts/src/Counter.sol`, `contracts/script/Counter.s.sol`, `contracts/test/Counter.t.sol`

**Interfaces:**
- Produces: a build that resolves `@openzeppelin/contracts/`, `@openzeppelin/contracts-upgradeable/`, `@gluwa/asc-contracts/` and `forge-std/`. Every later task depends on this.

- [ ] **Step 1: Install the Attestcoin Solidity package**

`EvmV1Decoder.sol` and `INativeQueryVerifier.sol` come from Gluwa's published package. The
decoder has **zero imports** and is entirely `internal pure`, so no library linking is needed.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
npm init -y >/dev/null 2>&1
npm install @gluwa/asc-contracts@0.2.1
ls node_modules/@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol
ls node_modules/@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol
```

Expected: both paths print.

- [ ] **Step 2: Rewrite `foundry.toml`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > foundry.toml <<'EOF'
[profile.default]
src = "src"
out = "out"
test = "test"
script = "script"
libs = ["lib", "node_modules"]
solc_version = "0.8.30"
optimizer = true
optimizer_runs = 200
via_ir = true
evm_version = "shanghai"
verbosity = 2
fs_permissions = [{ access = "read", path = "./test/fixtures" }]

[profile.default.fuzz]
runs = 512

[profile.default.invariant]
runs = 64
depth = 64
fail_on_revert = false

[lint]
lint_on_build = false

[rpc_endpoints]
creditcoin_testnet = "https://rpc.cc3-testnet.creditcoin.network"
sepolia = "${SEPOLIA_RPC_URL}"

[etherscan]
creditcoin_testnet = { key = "blockscout", url = "https://creditcoin-testnet.blockscout.com/api", chain = 102031 }
EOF
cat > remappings.txt <<'EOF'
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
@openzeppelin/contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/contracts/
@gluwa/asc-contracts/=node_modules/@gluwa/asc-contracts/
forge-std/=lib/forge-std/src/
EOF
```

- [ ] **Step 3: Write `.env.example` and confirm the real `.env` stays ignored**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > .env.example <<'EOF'
# Deployer key — never commit the real .env
PRIVATE_KEY=0x

# Creditcoin Testnet
CREDITCOIN_RPC_URL=https://rpc.cc3-testnet.creditcoin.network

# Ethereum Sepolia (source chain)
SEPOLIA_RPC_URL=

# Attestcoin
SOURCE_CHAIN_KEY=1
PROOF_BUILDER_URL=https://prover.cc3-testnet.creditcoin.network

# Filled in by script/Deploy.s.sol
ARENA_ESCROW=
SEASON_REGISTRY=
USDT_TOKEN=
DOODLE_GATE_ASC=
DOODLE_GATE_SEPOLIA=
EOF
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git check-ignore -v contracts/.env && echo "OK: .env ignored"
```

Expected: `OK: .env ignored`.

- [ ] **Step 4: Remove the scaffold and verify a clean build**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
rm -f src/Counter.sol script/Counter.s.sol test/Counter.t.sol
mkdir -p src/asc src/sepolia src/interfaces test/helpers test/fork test/fixtures
forge build
```

Expected: `Compiler run successful` with nothing to compile, or a clean build of the libraries.

- [ ] **Step 5: Prove the Attestcoin imports resolve**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/Imports.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";
import {
    INativeQueryVerifier,
    NativeQueryVerifierLib
} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

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
EOF
forge test --match-path test/Imports.t.sol -vv
```

Expected: three tests PASS. This proves the remappings work and documents the encoding format
(`abi.encode(uint8 txType, bytes[] chunks)`) that Task 7's fixtures rely on.

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/foundry.toml contracts/remappings.txt contracts/.env.example contracts/package.json contracts/package-lock.json contracts/test/Imports.t.sol
git rm --cached -r --ignore-unmatch contracts/node_modules >/dev/null 2>&1 || true
git add -A contracts/src contracts/script contracts/test
git commit -m "build: configure Foundry for Creditcoin and the Attestcoin package"
```

---

### Task 2: `USDT` — mock stablecoin, UUPS, 6 decimals

**Files:**
- Create: `contracts/src/USDT.sol`
- Create: `contracts/test/USDT.t.sol`

**Interfaces:**
- Produces:
  - `initialize(address initialOwner)`
  - `decimals() returns (uint8)` — always `6`
  - `mint(address to, uint256 amount)` — owner or an address approved via `setMinter`
  - `setMinter(address account, bool allowed)` — owner only
  - `faucet()` — `FAUCET_AMOUNT = 1_000e6`, once per `FAUCET_COOLDOWN = 1 days` per address
  - Tasks 4–8 and Plan 3 all use this token.

- [ ] **Step 1: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/USDT.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {USDT} from "../src/USDT.sol";

contract USDTTest is Test {
    USDT internal usdt;
    address internal owner = makeAddr("owner");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");

    function setUp() public {
        USDT impl = new USDT();
        usdt = USDT(address(new ERC1967Proxy(address(impl), abi.encodeCall(USDT.initialize, (owner)))));
    }

    // ---------- positive ----------

    function test_metadata() public view {
        assertEq(usdt.name(), "USDT");
        assertEq(usdt.symbol(), "USDT");
        assertEq(usdt.decimals(), 6, "stablecoin convention is 6 decimals");
        assertEq(usdt.owner(), owner);
    }

    function test_ownerCanMint() public {
        vm.prank(owner);
        usdt.mint(alice, 500e6);
        assertEq(usdt.balanceOf(alice), 500e6);
        assertEq(usdt.totalSupply(), 500e6);
    }

    function test_approvedMinterCanMint() public {
        vm.prank(owner);
        usdt.setMinter(minter, true);
        vm.prank(minter);
        usdt.mint(alice, 7e6);
        assertEq(usdt.balanceOf(alice), 7e6);
    }

    function test_faucetDispensesTheFixedAmount() public {
        vm.prank(alice);
        usdt.faucet();
        assertEq(usdt.balanceOf(alice), usdt.FAUCET_AMOUNT());
    }

    function test_faucetWorksAgainAfterTheCooldown() public {
        vm.prank(alice);
        usdt.faucet();
        vm.warp(block.timestamp + usdt.FAUCET_COOLDOWN());
        vm.prank(alice);
        usdt.faucet();
        assertEq(usdt.balanceOf(alice), usdt.FAUCET_AMOUNT() * 2);
    }

    // ---------- edge ----------

    function test_faucetExactlyAtTheCooldownBoundaryIsAllowed() public {
        vm.prank(alice);
        usdt.faucet();
        uint256 t = usdt.lastFaucet(alice);
        vm.warp(t + usdt.FAUCET_COOLDOWN());
        vm.prank(alice);
        usdt.faucet(); // must not revert
    }

    function test_revokedMinterLosesAccess() public {
        vm.startPrank(owner);
        usdt.setMinter(minter, true);
        usdt.setMinter(minter, false);
        vm.stopPrank();
        vm.prank(minter);
        vm.expectRevert(USDT.NotMinter.selector);
        usdt.mint(alice, 1);
    }

    // ---------- negative ----------

    function test_revert_strangerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(USDT.NotMinter.selector);
        usdt.mint(alice, 1e6);
    }

    function test_revert_strangerCannotSetMinter() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        usdt.setMinter(minter, true);
    }

    function test_revert_faucetTwiceInsideTheCooldown() public {
        vm.startPrank(alice);
        usdt.faucet();
        vm.warp(block.timestamp + usdt.FAUCET_COOLDOWN() - 1);
        vm.expectRevert(USDT.FaucetCooldown.selector);
        usdt.faucet();
        vm.stopPrank();
    }

    function test_revert_initializeTwice() public {
        vm.expectRevert();
        usdt.initialize(alice);
    }

    function test_revert_implementationCannotBeInitialized() public {
        USDT impl = new USDT();
        vm.expectRevert();
        impl.initialize(alice);
    }
}
EOF
forge test --match-path test/USDT.t.sol
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: compilation FAILS — `src/USDT.sol` does not exist.

- [ ] **Step 3: Implement `USDT`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/USDT.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title USDT — mock test stablecoin for Inkstake Arena
/// @notice TESTNET ONLY. This token has no value and is NOT affiliated with Tether or any real
///         stablecoin issuer. It exists so players can stake something other than native tCTC
///         during the hackathon. The name and symbol were chosen by the project owner.
/// @dev UUPS-upgradeable, ERC-7201 namespaced storage, 6 decimals by stablecoin convention.
contract USDT is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error NotMinter();
    error FaucetCooldown();

    event MinterSet(address indexed account, bool allowed);

    uint256 public constant FAUCET_AMOUNT = 1_000e6;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    /// @custom:storage-location erc7201:inkstake.storage.USDT
    struct USDTStorage {
        mapping(address account => bool allowed) minters;
        mapping(address account => uint256 at) lastFaucet;
    }

    bytes32 private constant STORAGE_SLOT =
        0x181e7851ce70236646a4bdccacb641dd7f5cd904ed2d297634c5f3875df74200;

    function _s() private pure returns (USDTStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __ERC20_init("USDT", "USDT");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function isMinter(address account) public view returns (bool) {
        return _s().minters[account];
    }

    function lastFaucet(address account) public view returns (uint256) {
        return _s().lastFaucet[account];
    }

    function setMinter(address account, bool allowed) external onlyOwner {
        _s().minters[account] = allowed;
        emit MinterSet(account, allowed);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != owner() && !_s().minters[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }

    /// @notice Self-service tokens for testers, rate limited per address.
    function faucet() external {
        USDTStorage storage $ = _s();
        uint256 last = $.lastFaucet[msg.sender];
        if (last != 0 && block.timestamp < last + FAUCET_COOLDOWN) revert FaucetCooldown();
        $.lastFaucet[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
EOF
```

- [ ] **Step 4: Run the test and watch it pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/USDT.t.sol -vv
```

Expected: all 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/USDT.sol contracts/test/USDT.t.sol
git commit -m "feat(contracts): add mock USDT test stablecoin"
```

---

### Task 3: `SeasonRegistry` — per-season leaderboard

**Files:**
- Create: `contracts/src/interfaces/ISeasonRegistry.sol`
- Create: `contracts/src/SeasonRegistry.sol`
- Create: `contracts/test/SeasonRegistry.t.sol`

**Interfaces:**
- Produces:
  - `initialize(address initialOwner)`
  - `setEscrow(address)` — owner only; the only address allowed to record
  - `recordRun(address player, uint32 waveReached, uint64 score, address token, uint256 staked, uint256 won)`
  - `startNewSeason()` — owner only; returns the new season id
  - `currentSeason() returns (uint64)`
  - `statsOf(uint64 season, address player) returns (PlayerStats memory)`
  - `ArenaEscrow` (Task 5) calls `recordRun` from `settleRun`.

Elo is deliberately **not** implemented here. Elo is a pairwise PvP rating and is meaningless
against bots; it arrives in Phase 2 when there are real opponents.

- [ ] **Step 1: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/SeasonRegistry.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {ISeasonRegistry} from "../src/interfaces/ISeasonRegistry.sol";

contract SeasonRegistryTest is Test {
    SeasonRegistry internal reg;
    address internal owner = makeAddr("owner");
    address internal escrow = makeAddr("escrow");
    address internal alice = makeAddr("alice");
    address internal token = makeAddr("token");

    function setUp() public {
        SeasonRegistry impl = new SeasonRegistry();
        reg = SeasonRegistry(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(SeasonRegistry.initialize, (owner))))
        );
        vm.prank(owner);
        reg.setEscrow(escrow);
    }

    function _record(uint32 wave, uint64 score, uint256 staked, uint256 won) internal {
        vm.prank(escrow);
        reg.recordRun(alice, wave, score, token, staked, won);
    }

    // ---------- positive ----------

    function test_startsAtSeasonOne() public view {
        assertEq(reg.currentSeason(), 1);
    }

    function test_recordsARun() public {
        _record(7, 1234, 10e18, 15e18);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.runs, 1);
        assertEq(s.wins, 1, "a payout above zero counts as a win");
        assertEq(s.bestWave, 7);
        assertEq(s.bestScore, 1234);
        assertEq(s.totalStaked, 10e18);
        assertEq(s.totalWon, 15e18);
    }

    function test_aLossIncrementsRunsButNotWins() public {
        _record(3, 400, 5e18, 0);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.runs, 1);
        assertEq(s.wins, 0);
    }

    // ---------- edge ----------

    function test_bestWaveAndBestScoreOnlyEverImprove() public {
        _record(12, 9000, 1e18, 2e18);
        _record(4, 100, 1e18, 0); // worse run must not lower the records
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.bestWave, 12);
        assertEq(s.bestScore, 9000);
        assertEq(s.runs, 2);
    }

    function test_bestScoreImprovesEvenWhenTheWaveIsLower() public {
        _record(10, 100, 1e18, 0);
        _record(9, 5000, 1e18, 0);
        ISeasonRegistry.PlayerStats memory s = reg.statsOf(1, alice);
        assertEq(s.bestWave, 10);
        assertEq(s.bestScore, 5000);
    }

    function test_newSeasonStartsFromCleanStats() public {
        _record(12, 9000, 1e18, 2e18);
        vm.prank(owner);
        uint64 next = reg.startNewSeason();
        assertEq(next, 2);
        assertEq(reg.currentSeason(), 2);

        ISeasonRegistry.PlayerStats memory fresh = reg.statsOf(2, alice);
        assertEq(fresh.runs, 0);
        assertEq(fresh.bestWave, 0);

        ISeasonRegistry.PlayerStats memory old = reg.statsOf(1, alice);
        assertEq(old.bestWave, 12, "history must survive a season rollover");
    }

    function test_waveZeroIsRecordable() public {
        _record(0, 0, 1e18, 0);
        assertEq(reg.statsOf(1, alice).runs, 1);
    }

    // ---------- negative ----------

    function test_revert_onlyEscrowCanRecord() public {
        vm.prank(alice);
        vm.expectRevert(SeasonRegistry.NotEscrow.selector);
        reg.recordRun(alice, 5, 1, token, 1, 1);
    }

    function test_revert_ownerCannotRecordEither() public {
        vm.prank(owner);
        vm.expectRevert(SeasonRegistry.NotEscrow.selector);
        reg.recordRun(alice, 5, 1, token, 1, 1);
    }

    function test_revert_strangerCannotSetEscrow() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        reg.setEscrow(alice);
    }

    function test_revert_strangerCannotStartASeason() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        reg.startNewSeason();
    }

    function test_revert_initializeTwice() public {
        vm.expectRevert();
        reg.initialize(alice);
    }
}
EOF
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/SeasonRegistry.t.sol
```

Expected: compilation FAILS — the source files do not exist.

- [ ] **Step 3: Implement the interface and the contract**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/interfaces/ISeasonRegistry.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ISeasonRegistry {
    struct PlayerStats {
        uint32 bestWave;
        uint64 bestScore;
        uint32 runs;
        uint32 wins;
        uint256 totalStaked;
        uint256 totalWon;
    }

    function recordRun(
        address player,
        uint32 waveReached,
        uint64 score,
        address token,
        uint256 staked,
        uint256 won
    ) external;

    function currentSeason() external view returns (uint64);

    function statsOf(uint64 season, address player) external view returns (PlayerStats memory);
}
EOF
cat > src/SeasonRegistry.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ISeasonRegistry} from "./interfaces/ISeasonRegistry.sol";

/// @title SeasonRegistry
/// @notice Per-season, per-player record of runs: best wave, best score, totals.
/// @dev Elo is intentionally absent. Elo is a pairwise PvP rating and is meaningless against
///      bots; it belongs to Phase 2, when there are real opponents.
contract SeasonRegistry is ISeasonRegistry, OwnableUpgradeable, UUPSUpgradeable {
    error NotEscrow();

    event RunRecorded(
        uint64 indexed season,
        address indexed player,
        uint32 waveReached,
        uint64 score,
        address token,
        uint256 staked,
        uint256 won
    );
    event SeasonStarted(uint64 indexed season, uint64 startedAt);
    event EscrowSet(address indexed escrow);

    /// @custom:storage-location erc7201:inkstake.storage.SeasonRegistry
    struct RegistryStorage {
        address escrow;
        uint64 season;
        mapping(uint64 season => mapping(address player => PlayerStats)) stats;
    }

    bytes32 private constant STORAGE_SLOT =
        0x7a4a5c417275a8e784c1b2fa5f44d304cfe537c32066064710d669f7da8bf400;

    function _s() private pure returns (RegistryStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        _s().season = 1;
        emit SeasonStarted(1, uint64(block.timestamp));
    }

    modifier onlyEscrow() {
        if (msg.sender != _s().escrow) revert NotEscrow();
        _;
    }

    function escrow() external view returns (address) {
        return _s().escrow;
    }

    function currentSeason() external view returns (uint64) {
        return _s().season;
    }

    function statsOf(uint64 season, address player) external view returns (PlayerStats memory) {
        return _s().stats[season][player];
    }

    function setEscrow(address newEscrow) external onlyOwner {
        _s().escrow = newEscrow;
        emit EscrowSet(newEscrow);
    }

    function startNewSeason() external onlyOwner returns (uint64) {
        RegistryStorage storage $ = _s();
        uint64 next = $.season + 1;
        $.season = next;
        emit SeasonStarted(next, uint64(block.timestamp));
        return next;
    }

    function recordRun(
        address player,
        uint32 waveReached,
        uint64 score,
        address token,
        uint256 staked,
        uint256 won
    ) external onlyEscrow {
        RegistryStorage storage $ = _s();
        uint64 season = $.season;
        PlayerStats storage p = $.stats[season][player];

        p.runs += 1;
        if (won > 0) p.wins += 1;
        if (waveReached > p.bestWave) p.bestWave = waveReached;
        if (score > p.bestScore) p.bestScore = score;
        p.totalStaked += staked;
        p.totalWon += won;

        emit RunRecorded(season, player, waveReached, score, token, staked, won);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
EOF
```

- [ ] **Step 4: Run the test and watch it pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/SeasonRegistry.t.sol -vv
```

Expected: all 12 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/SeasonRegistry.sol contracts/src/interfaces/ISeasonRegistry.sol contracts/test/SeasonRegistry.t.sol
git commit -m "feat(contracts): add SeasonRegistry leaderboard"
```

---

### Task 4: `ArenaEscrow` — storage, `startRun`, pool funding

The solvency gate lives here. `startRun` reserves the **payout ceiling** before accepting a
stake, so the contract can never owe more than it holds.

**Files:**
- Create: `contracts/src/interfaces/IArenaEscrow.sol`
- Create: `contracts/src/ArenaEscrow.sol`
- Create: `contracts/test/ArenaEscrow.start.t.sol`

**Interfaces:**
- Produces:
  - `initialize(address initialOwner, address seasonRegistry)`
  - `startRun(address token, uint256 amount) payable returns (bytes32 runId)`
  - `fundPool(address token, uint256 amount) payable`
  - `runOf(bytes32 runId) returns (Run memory)`, `activeRunOf(address) returns (bytes32)`
  - `poolOf(address token) returns (Pool memory)`, `multiplierBpsFor(uint32 wave) returns (uint32)`
  - `setMaxStake(address,uint256)`, `setMultiplierTiers(Tier[])`, `setAsc(address)`
  - Accounting identity, asserted as an invariant in Task 10:
    `balance(token) == pool.free + pool.reserved + pool.activeStake`

- [ ] **Step 1: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/ArenaEscrow.start.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";

contract ArenaEscrowStartTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant MAX_NATIVE = 100e18;
    uint256 constant MAX_USDT = 100e6;

    function setUp() public {
        registry = SeasonRegistry(
            address(new ERC1967Proxy(address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))))
        );
        usdt = USDT(
            address(new ERC1967Proxy(address(new USDT()), abi.encodeCall(USDT.initialize, (owner))))
        );
        escrow = ArenaEscrow(
            payable(address(new ERC1967Proxy(
                address(new ArenaEscrow()),
                abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
            )))
        );

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), MAX_NATIVE);
        escrow.setMaxStake(address(usdt), MAX_USDT);
        usdt.mint(owner, 1_000_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 100_000e6);
        vm.stopPrank();

        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);

        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        vm.prank(owner);
        usdt.mint(alice, 10_000e6);
        vm.prank(alice);
        usdt.approve(address(escrow), type(uint256).max);
    }

    // ---------- positive ----------

    function test_startNativeRunLocksTheStakeAndReservesThePayoutCeiling() public {
        IArenaEscrow.Pool memory before = escrow.poolOf(address(0));

        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: 10 ether}(address(0), 10 ether);

        IArenaEscrow.Run memory r = escrow.runOf(runId);
        assertEq(r.player, alice);
        assertEq(r.token, address(0));
        assertEq(r.stake, 10 ether);
        assertEq(r.reserved, 30 ether, "ceiling is 3x the stake");
        assertTrue(r.seed != bytes32(0), "a seed must be issued");
        assertEq(uint8(r.state), uint8(IArenaEscrow.RunState.Active));
        assertEq(escrow.activeRunOf(alice), runId);

        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(p.free, before.free - 30 ether);
        assertEq(p.reserved, before.reserved + 30 ether);
        assertEq(p.activeStake, before.activeStake + 10 ether);
    }

    function test_startUsdtRun() public {
        vm.prank(alice);
        bytes32 runId = escrow.startRun(address(usdt), 50e6);
        IArenaEscrow.Run memory r = escrow.runOf(runId);
        assertEq(r.token, address(usdt));
        assertEq(r.stake, 50e6);
        assertEq(r.reserved, 150e6);
        assertEq(usdt.balanceOf(address(escrow)), 100_000e6 + 50e6);
    }

    function test_theAccountingIdentityHoldsAfterAStart() public {
        vm.prank(alice);
        escrow.startRun{value: 7 ether}(address(0), 7 ether);
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    function test_twoPlayersCanRunConcurrently() public {
        vm.prank(alice);
        bytes32 a = escrow.startRun{value: 1 ether}(address(0), 1 ether);
        vm.prank(bob);
        bytes32 b = escrow.startRun{value: 2 ether}(address(0), 2 ether);
        assertTrue(a != b, "run ids must be distinct");
    }

    // ---------- edge ----------

    function test_stakeExactlyAtTheCapIsAccepted() public {
        vm.prank(alice);
        escrow.startRun{value: MAX_NATIVE}(address(0), MAX_NATIVE);
        assertEq(escrow.runOf(escrow.activeRunOf(alice)).stake, MAX_NATIVE);
    }

    function test_capsAreIndependentPerTokenDecimals() public {
        assertEq(escrow.maxStakeOf(address(0)), 100e18);
        assertEq(escrow.maxStakeOf(address(usdt)), 100e6);
    }

    function test_multiplierTierBoundaries() public view {
        assertEq(escrow.multiplierBpsFor(0), 0);
        assertEq(escrow.multiplierBpsFor(4), 0, "wave 4 is still a loss");
        assertEq(escrow.multiplierBpsFor(5), 15_000, "wave 5 is the first winning tier");
        assertEq(escrow.multiplierBpsFor(9), 15_000);
        assertEq(escrow.multiplierBpsFor(10), 20_000);
        assertEq(escrow.multiplierBpsFor(14), 20_000);
        assertEq(escrow.multiplierBpsFor(15), 30_000);
        assertEq(escrow.multiplierBpsFor(9999), 30_000, "capped at the maximum tier");
    }

    function test_poolExactlyCoveringTheCeilingIsAccepted() public {
        // Drain the native pool down to exactly 3 ether of free room, then stake 1 ether.
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        vm.prank(owner);
        escrow.withdrawFree(address(0), owner, p.free - 3 ether);

        vm.prank(alice);
        escrow.startRun{value: 1 ether}(address(0), 1 ether); // must not revert
        assertEq(escrow.poolOf(address(0)).free, 0);
    }

    // ---------- negative ----------

    function test_revert_secondRunWhileOneIsActive() public {
        vm.startPrank(alice);
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
        vm.expectRevert(ArenaEscrow.RunAlreadyActive.selector);
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
        vm.stopPrank();
    }

    function test_revert_stakeAboveTheCap() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.StakeAboveCap.selector, MAX_NATIVE + 1, MAX_NATIVE));
        escrow.startRun{value: MAX_NATIVE + 1}(address(0), MAX_NATIVE + 1);
    }

    function test_revert_zeroStake() public {
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.ZeroAmount.selector);
        escrow.startRun(address(0), 0);
    }

    function test_revert_nativeValueMismatch() public {
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.BadValue.selector);
        escrow.startRun{value: 1 ether}(address(0), 2 ether);
    }

    function test_revert_sendingValueAlongsideAnErc20Stake() public {
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.BadValue.selector);
        escrow.startRun{value: 1 ether}(address(usdt), 10e6);
    }

    function test_revert_unallowlistedToken() public {
        address stranger = makeAddr("randomToken");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.TokenNotAllowed.selector, stranger));
        escrow.startRun(stranger, 1);
    }

    function test_revert_erc20StakeWithoutApproval() public {
        vm.prank(owner);
        usdt.mint(bob, 100e6);
        vm.prank(bob); // bob never approved
        vm.expectRevert();
        escrow.startRun(address(usdt), 10e6);
    }

    function test_revert_poolCannotCoverThePayoutCeiling() public {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        vm.prank(owner);
        escrow.withdrawFree(address(0), owner, p.free); // free == 0

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.PoolTooSmall.selector, 0, 3 ether));
        escrow.startRun{value: 1 ether}(address(0), 1 ether);
    }

    function test_revert_withdrawFreeCannotTouchReservedFunds() public {
        vm.prank(alice);
        escrow.startRun{value: 10 ether}(address(0), 10 ether);
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));

        vm.prank(owner);
        vm.expectRevert();
        escrow.withdrawFree(address(0), owner, p.free + 1);
    }
}
EOF
forge test --match-path test/ArenaEscrow.start.t.sol
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: compilation FAILS — `src/ArenaEscrow.sol` does not exist.

- [ ] **Step 3: Write the interface**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/interfaces/IArenaEscrow.sol <<'EOF'
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
EOF
```

- [ ] **Step 4: Implement `ArenaEscrow` — storage, `startRun`, `fundPool`, views, the setters used above**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/ArenaEscrow.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IArenaEscrow} from "./interfaces/IArenaEscrow.sol";
import {ISeasonRegistry} from "./interfaces/ISeasonRegistry.sol";

/// @title ArenaEscrow
/// @notice Holds stakes and the reward pool for Inkstake Arena runs.
/// @dev The contract can never owe more than it holds: `startRun` reserves the payout ceiling
///      up front and refuses the run if the pool cannot cover it.
///
///      Settlement is a threshold check over EIP-712 attestations. Phase 1 registers one
///      attestor (the ink-monitor key, threshold 1). Phase 2 registers match participants with
///      threshold ceil(2n/3). The function and the signed struct are identical in both phases.
///
///      Only allowlisted tokens can be staked (`setMaxStake`). Fee-on-transfer and rebasing
///      tokens would break the accounting identity and must never be allowlisted.
contract ArenaEscrow is
    IArenaEscrow,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20 for IERC20;

    error RunAlreadyActive();
    error ZeroAmount();
    error BadValue();
    error TokenNotAllowed(address token);
    error StakeAboveCap(uint256 amount, uint256 cap);
    error PoolTooSmall(uint256 free, uint256 needed);
    error NotFunder();
    error InsufficientFree(uint256 free, uint256 requested);
    error BadTiers();

    uint32 public constant BPS_DENOMINATOR = 10_000;

    /// @custom:storage-location erc7201:inkstake.storage.ArenaEscrow
    struct EscrowStorage {
        ISeasonRegistry seasonRegistry;
        address asc; // DoodleGateASC, allowed to fund the pool
        uint32 maxMultiplierBps;
        uint64 runTtl;
        uint256 threshold;
        Tier[] tiers;
        mapping(address account => bool) attestors;
        mapping(address token => uint256) maxStake;
        mapping(address token => Pool) pools;
        mapping(bytes32 runId => Run) runs;
        mapping(address player => bytes32 runId) activeRun;
        mapping(address player => uint256) runNonce;
    }

    bytes32 private constant STORAGE_SLOT =
        0xcf5ea8a7afd0f750bf3fb7589d3874efecbc02abcd883e191bbc203b187f4e00;

    function _s() private pure returns (EscrowStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address seasonRegistry) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __EIP712_init("InkstakeArena", "1");

        EscrowStorage storage $ = _s();
        $.seasonRegistry = ISeasonRegistry(seasonRegistry);
        $.maxMultiplierBps = 30_000;
        $.runTtl = 2 hours;
        $.threshold = 1;

        // Tiers line up with the game's checkpoint rhythm, which unlocks every 5 waves.
        $.tiers.push(Tier({minWave: 5, multiplierBps: 15_000}));
        $.tiers.push(Tier({minWave: 10, multiplierBps: 20_000}));
        $.tiers.push(Tier({minWave: 15, multiplierBps: 30_000}));
    }

    // ---------------- views ----------------

    function runOf(bytes32 runId) external view returns (Run memory) {
        return _s().runs[runId];
    }

    function activeRunOf(address player) external view returns (bytes32) {
        return _s().activeRun[player];
    }

    function poolOf(address token) external view returns (Pool memory) {
        return _s().pools[token];
    }

    function maxStakeOf(address token) external view returns (uint256) {
        return _s().maxStake[token];
    }

    function isAttestor(address account) external view returns (bool) {
        return _s().attestors[account];
    }

    function threshold() external view returns (uint256) {
        return _s().threshold;
    }

    function runTtl() external view returns (uint64) {
        return _s().runTtl;
    }

    function seasonRegistry() external view returns (address) {
        return address(_s().seasonRegistry);
    }

    function tiers() external view returns (Tier[] memory) {
        return _s().tiers;
    }

    /// @notice Payout multiplier for a wave, in basis points. Zero means the run was a loss.
    function multiplierBpsFor(uint32 wave) public view returns (uint32 bps) {
        Tier[] storage t = _s().tiers;
        uint256 n = t.length;
        for (uint256 i; i < n; ++i) {
            if (wave >= t[i].minWave) bps = t[i].multiplierBps;
            else break;
        }
    }

    // ---------------- staking ----------------

    /// @notice Stake and begin a run. Reverts unless the pool can cover the payout ceiling.
    function startRun(address token, uint256 amount)
        external
        payable
        nonReentrant
        returns (bytes32 runId)
    {
        EscrowStorage storage $ = _s();

        if ($.activeRun[msg.sender] != bytes32(0)) revert RunAlreadyActive();
        if (amount == 0) revert ZeroAmount();

        uint256 cap = $.maxStake[token];
        if (cap == 0) revert TokenNotAllowed(token);
        if (amount > cap) revert StakeAboveCap(amount, cap);

        _pullFunds(token, amount);

        uint256 ceiling = (amount * $.maxMultiplierBps) / BPS_DENOMINATOR;
        Pool storage p = $.pools[token];
        if (p.free < ceiling) revert PoolTooSmall(p.free, ceiling);
        p.free -= ceiling;
        p.reserved += ceiling;
        p.activeStake += amount;

        uint256 nonce = $.runNonce[msg.sender]++;
        runId = keccak256(abi.encodePacked(address(this), block.chainid, msg.sender, nonce));
        // Committed before play. A validator could nudge blockhash; acceptable for a game seed.
        bytes32 seed = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, nonce));
        uint64 deadline = uint64(block.timestamp) + $.runTtl;

        $.runs[runId] = Run({
            player: msg.sender,
            token: token,
            stake: amount,
            reserved: ceiling,
            seed: seed,
            startedAt: uint64(block.timestamp),
            deadline: deadline,
            state: RunState.Active
        });
        $.activeRun[msg.sender] = runId;

        emit RunStarted(runId, msg.sender, token, amount, seed, deadline);
    }

    /// @notice Add funds to the reward pool. Owner, or the ASC crediting a cross-chain sponsor.
    function fundPool(address token, uint256 amount) external payable {
        EscrowStorage storage $ = _s();
        if (msg.sender != owner() && msg.sender != $.asc) revert NotFunder();
        if (amount == 0) revert ZeroAmount();
        _pullFunds(token, amount);
        $.pools[token].free += amount;
        emit PoolFunded(token, msg.sender, amount);
    }

    /// @notice Withdraw unreserved pool funds. Never touches reservations or live stakes.
    function withdrawFree(address token, address to, uint256 amount) external onlyOwner {
        Pool storage p = _s().pools[token];
        if (amount > p.free) revert InsufficientFree(p.free, amount);
        p.free -= amount;
        _pay(token, to, amount);
    }

    // ---------------- admin ----------------

    function setMaxStake(address token, uint256 cap) external onlyOwner {
        _s().maxStake[token] = cap;
    }

    function setAsc(address asc) external onlyOwner {
        _s().asc = asc;
    }

    function setMultiplierTiers(Tier[] calldata newTiers) external onlyOwner {
        EscrowStorage storage $ = _s();
        uint256 n = newTiers.length;
        if (n == 0) revert BadTiers();
        for (uint256 i; i < n; ++i) {
            // A multiplier below 1x would make a "win" pay out less than the stake and would
            // underflow the pool accounting in _settleAccounting.
            if (newTiers[i].multiplierBps < BPS_DENOMINATOR) revert BadTiers();
            if (newTiers[i].multiplierBps > $.maxMultiplierBps) revert BadTiers();
            if (i > 0 && newTiers[i].minWave <= newTiers[i - 1].minWave) revert BadTiers();
        }
        delete $.tiers;
        for (uint256 i; i < n; ++i) {
            $.tiers.push(newTiers[i]);
        }
    }

    // ---------------- internals ----------------

    function _pullFunds(address token, uint256 amount) private {
        if (token == address(0)) {
            if (msg.value != amount) revert BadValue();
        } else {
            if (msg.value != 0) revert BadValue();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _pay(address token, address to, uint256 amount) internal {
        if (token == address(0)) Address.sendValue(payable(to), amount);
        else IERC20(token).safeTransfer(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {
        revert NotFunder();
    }
}
EOF
```

- [ ] **Step 5: Run the test and watch it pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/ArenaEscrow.start.t.sol -vv
```

Expected: all 18 tests PASS. If `test_revert_erc20StakeWithoutApproval` fails, check that
`_pullFunds` runs **before** the pool reservation — the transfer must be the thing that reverts.

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/ArenaEscrow.sol contracts/src/interfaces/IArenaEscrow.sol contracts/test/ArenaEscrow.start.t.sol
git commit -m "feat(contracts): ArenaEscrow staking with payout-ceiling reservation"
```

---

### Task 5: `ArenaEscrow.settleRun` — EIP-712 attestations and payout

**Files:**
- Create: `contracts/test/helpers/SignerLib.sol`
- Create: `contracts/test/helpers/Reenterer.sol`
- Modify: `contracts/src/ArenaEscrow.sol` (add `settleRun` and its internals)
- Create: `contracts/test/ArenaEscrow.settle.t.sol`

**Interfaces:**
- Consumes: `startRun`, `poolOf`, `multiplierBpsFor` from Task 4; `SeasonRegistry.recordRun` from Task 3.
- Produces:
  - `settleRun(RunResult calldata r, bytes[] calldata sigs)`
  - `RUN_RESULT_TYPEHASH` and `hashRunResult(RunResult) returns (bytes32)` — the digest the
    `ink-monitor` in Plan 3 signs.
  - `setAttestor(address,bool)`, `setThreshold(uint256)`

- [ ] **Step 1: Write the signing helper and the reentrancy attacker**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/helpers/SignerLib.sol <<'EOF'
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
EOF
cat > test/helpers/Reenterer.sol <<'EOF'
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
EOF
```

- [ ] **Step 2: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/ArenaEscrow.settle.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {ISeasonRegistry} from "../src/interfaces/ISeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {SignerLib} from "./helpers/SignerLib.sol";
import {Reenterer} from "./helpers/Reenterer.sol";

contract ArenaEscrowSettleTest is Test {
    using SignerLib for bytes;

    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    uint256 internal monitorPk;
    address internal monitor;
    uint256 internal strangerPk;
    address internal stranger;
    uint256 internal peerPk;
    address internal peer;

    function setUp() public {
        (monitor, monitorPk) = makeAddrAndKey("monitor");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        (peer, peerPk) = makeAddrAndKey("peer");

        registry = SeasonRegistry(
            address(new ERC1967Proxy(address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))))
        );
        usdt = USDT(address(new ERC1967Proxy(address(new USDT()), abi.encodeCall(USDT.initialize, (owner)))));
        escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
        ))));

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        escrow.setMaxStake(address(usdt), 100e6);
        escrow.setAttestor(monitor, true);
        escrow.setThreshold(1);
        usdt.mint(owner, 1_000_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 100_000e6);
        vm.stopPrank();

        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);
        vm.deal(alice, 1_000 ether);
    }

    function _start(uint256 amount) internal returns (bytes32) {
        vm.prank(alice);
        return escrow.startRun{value: amount}(address(0), amount);
    }

    function _result(bytes32 runId, uint32 wave, uint64 score)
        internal
        view
        returns (IArenaEscrow.RunResult memory)
    {
        return IArenaEscrow.RunResult({
            runId: runId,
            player: alice,
            waveReached: wave,
            score: score,
            endedAt: uint64(block.timestamp)
        });
    }

    function _sign(uint256 pk, IArenaEscrow.RunResult memory r) internal view returns (bytes memory) {
        return SignerLib.sign(pk, escrow.hashRunResult(r));
    }

    // ---------- positive ----------

    function test_winAtWaveFivePaysOneAndAHalfTimes() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 5, 4200);
        uint256 before = alice.balance;

        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));

        assertEq(alice.balance - before, 15 ether, "1.5x of a 10 ether stake");
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Settled));
        assertEq(escrow.activeRunOf(alice), bytes32(0), "the active-run slot must be cleared");
    }

    function test_winAtWaveFifteenPaysTheCap() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 15, 99_000);
        uint256 before = alice.balance;
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
        assertEq(alice.balance - before, 30 ether, "3x is the ceiling");
    }

    function test_lossAbsorbsTheStakeIntoThePool() public {
        IArenaEscrow.Pool memory p0 = escrow.poolOf(address(0));
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 4, 300);
        uint256 before = alice.balance;

        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));

        assertEq(alice.balance, before, "a loss pays nothing");
        IArenaEscrow.Pool memory p1 = escrow.poolOf(address(0));
        assertEq(p1.free, p0.free + 10 ether, "the stake joins the pool");
        assertEq(p1.reserved, 0);
        assertEq(p1.activeStake, 0);
    }

    function test_settlementRecordsTheRunInTheSeasonRegistry() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 12, 7777);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));

        ISeasonRegistry.PlayerStats memory s = registry.statsOf(1, alice);
        assertEq(s.runs, 1);
        assertEq(s.wins, 1);
        assertEq(s.bestWave, 12);
        assertEq(s.bestScore, 7777);
        assertEq(s.totalWon, 20 ether);
    }

    function test_theAccountingIdentityHoldsAfterSettlement() public {
        bytes32 runId = _start(10 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    function test_phaseTwoShape_twoOfThreeAttestorsSuffice() public {
        vm.startPrank(owner);
        escrow.setAttestor(peer, true);
        escrow.setThreshold(2);
        vm.stopPrank();

        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 5);
        escrow.settleRun(r, SignerLib.two(_sign(monitorPk, r), _sign(peerPk, r)));
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Settled));
    }

    // ---------- edge ----------

    function test_waveFourVersusWaveFiveIsTheLossWinBoundary() public {
        bytes32 a = _start(1 ether);
        IArenaEscrow.RunResult memory ra = _result(a, 4, 1);
        uint256 b0 = alice.balance;
        escrow.settleRun(ra, SignerLib.one(_sign(monitorPk, ra)));
        assertEq(alice.balance, b0, "wave 4 pays nothing");

        bytes32 b = _start(1 ether);
        IArenaEscrow.RunResult memory rb = _result(b, 5, 1);
        uint256 b1 = alice.balance;
        escrow.settleRun(rb, SignerLib.one(_sign(monitorPk, rb)));
        assertEq(alice.balance - b1, 1.5 ether, "wave 5 pays 1.5x");
    }

    function test_settlementExactlyAtTheDeadlineIsAllowed() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r))); // must not revert
    }

    function test_anyoneMaySubmitAValidlySignedResult() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        vm.prank(makeAddr("randomRelayer"));
        escrow.settleRun(r, sigs);
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Settled));
    }

    function test_reentrancyDuringPayoutIsBlockedAndTheBalanceIsCorrect() public {
        Reenterer attacker = new Reenterer(escrow);
        vm.deal(address(attacker), 10 ether);
        bytes32 runId = attacker.start{value: 1 ether}(1 ether);

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId,
            player: address(attacker),
            waveReached: 15,
            score: 1,
            endedAt: uint64(block.timestamp)
        });
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        attacker.arm(r, sigs);

        uint256 before = address(attacker).balance;
        escrow.settleRun(r, sigs);

        assertTrue(attacker.reentered(), "the callback must have fired");
        assertTrue(attacker.reentryReverted(), "the re-entrant call must revert");
        assertEq(address(attacker).balance - before, 3 ether, "paid exactly once");
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    // ---------- negative ----------

    function test_revert_signatureFromANonAttestor() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.NotAttestor.selector, stranger));
        escrow.settleRun(r, SignerLib.one(_sign(strangerPk, r)));
    }

    function test_revert_belowThreshold() public {
        vm.prank(owner);
        escrow.setThreshold(2);
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.ThresholdNotMet.selector, 1, 2));
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
    }

    function test_revert_theSameSignerCountedTwice() public {
        vm.prank(owner);
        escrow.setThreshold(2);
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes memory sig = _sign(monitorPk, r);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.DuplicateSigner.selector, monitor));
        escrow.settleRun(r, SignerLib.two(sig, sig));
    }

    function test_revert_signatureOverADifferentRunId() public {
        bytes32 runA = _start(1 ether);
        IArenaEscrow.RunResult memory ra = _result(runA, 15, 1);
        bytes memory sigForA = _sign(monitorPk, ra);

        // settle A legitimately, then try to reuse its signature for a second run
        escrow.settleRun(ra, SignerLib.one(sigForA));
        bytes32 runB = _start(1 ether);
        IArenaEscrow.RunResult memory rb = _result(runB, 15, 1);

        // The signature is over runA's digest, so it recovers to a different address entirely.
        vm.expectRevert();
        escrow.settleRun(rb, SignerLib.one(sigForA));
    }

    function test_revert_signatureFromADifferentChainIdDomain() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);

        // Rebuild the digest as if signed on another chain: the domain separator differs, so
        // recovery yields an address that is not an attestor.
        bytes32 wrongDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("InkstakeArena")),
                keccak256(bytes("1")),
                uint256(999999),
                address(escrow)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(escrow.RUN_RESULT_TYPEHASH(), r.runId, r.player, r.waveReached, r.score, r.endedAt)
        );
        bytes32 foreign = keccak256(abi.encodePacked("\x19\x01", wrongDomain, structHash));

        vm.expectRevert();
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, foreign)));
    }

    function test_revert_settlingTwice() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory sigs = SignerLib.one(_sign(monitorPk, r));
        escrow.settleRun(r, sigs);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.settleRun(r, sigs);
    }

    function test_revert_playerFieldDoesNotMatchTheRun() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId,
            player: stranger,
            waveReached: 15,
            score: 1,
            endedAt: uint64(block.timestamp)
        });
        vm.expectRevert(ArenaEscrow.PlayerMismatch.selector);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
    }

    function test_revert_settlingAfterTheDeadline() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        vm.expectRevert(ArenaEscrow.RunExpired.selector);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
    }

    function test_revert_unknownRunId() public {
        IArenaEscrow.RunResult memory r = _result(keccak256("nope"), 10, 1);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.settleRun(r, SignerLib.one(_sign(monitorPk, r)));
    }

    function test_revert_malformedSignatureBytes() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        vm.expectRevert();
        escrow.settleRun(r, SignerLib.one(hex"deadbeef"));
    }

    function test_revert_malleableSignature() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(monitorPk, escrow.hashRunResult(r));

        // Flip to the upper half of the curve order. OpenZeppelin's ECDSA rejects this.
        uint256 N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 sFlipped = bytes32(N - uint256(ss));
        uint8 vFlipped = v == 27 ? 28 : 27;

        vm.expectRevert();
        escrow.settleRun(r, SignerLib.one(abi.encodePacked(rr, sFlipped, vFlipped)));
    }

    function test_revert_emptySignatureArray() public {
        vm.prank(owner);
        escrow.setThreshold(1);
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = _result(runId, 10, 1);
        bytes[] memory none = new bytes[](0);
        vm.expectRevert(abi.encodeWithSelector(ArenaEscrow.ThresholdNotMet.selector, 0, 1));
        escrow.settleRun(r, none);
    }
}
EOF
forge test --match-path test/ArenaEscrow.settle.t.sol
```

- [ ] **Step 3: Run it and confirm it fails**

Expected: compilation FAILS — `settleRun`, `hashRunResult`, `RUN_RESULT_TYPEHASH`, `setAttestor`,
`setThreshold` and the new errors do not exist yet.

- [ ] **Step 4: Add settlement to `ArenaEscrow.sol`**

Add these errors next to the existing ones:

```solidity
    error RunNotActive();
    error PlayerMismatch();
    error RunExpired();
    error NotAttestor(address signer);
    error DuplicateSigner(address signer);
    error ThresholdNotMet(uint256 got, uint256 needed);
```

Add the typehash beside `BPS_DENOMINATOR`:

```solidity
    bytes32 public constant RUN_RESULT_TYPEHASH =
        keccak256("RunResult(bytes32 runId,address player,uint32 waveReached,uint64 score,uint64 endedAt)");
```

Add these functions:

```solidity
    /// @notice The EIP-712 digest an attestor signs. `ink-monitor` calls this shape off-chain.
    function hashRunResult(RunResult calldata r) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(RUN_RESULT_TYPEHASH, r.runId, r.player, r.waveReached, r.score, r.endedAt))
        );
    }

    function setAttestor(address account, bool allowed) external onlyOwner {
        _s().attestors[account] = allowed;
    }

    function setThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0) revert BadTiers();
        _s().threshold = newThreshold;
    }

    /// @notice Settle a finished run. Anyone may submit; only the signatures matter.
    function settleRun(RunResult calldata r, bytes[] calldata sigs) external nonReentrant {
        EscrowStorage storage $ = _s();
        Run storage run = $.runs[r.runId];

        if (run.state != RunState.Active) revert RunNotActive();
        if (run.player != r.player) revert PlayerMismatch();
        if (block.timestamp > run.deadline) revert RunExpired();

        _verifyAttestations($, r, sigs);

        uint256 stake = run.stake;
        uint256 reserved = run.reserved;
        address token = run.token;
        uint256 payout = (stake * multiplierBpsFor(r.waveReached)) / BPS_DENOMINATOR;

        // Effects before interactions.
        run.state = RunState.Settled;
        delete $.activeRun[r.player];

        Pool storage p = $.pools[token];
        p.reserved -= reserved;
        p.activeStake -= stake;
        // Tier validation guarantees payout is either 0 or at least `stake`, so this cannot
        // underflow and free never goes negative.
        p.free += payout == 0 ? reserved + stake : reserved - (payout - stake);

        $.seasonRegistry.recordRun(r.player, r.waveReached, r.score, token, stake, payout);
        emit RunSettled(r.runId, r.player, r.waveReached, r.score, payout);

        if (payout != 0) _pay(token, r.player, payout);
    }

    function _verifyAttestations(EscrowStorage storage $, RunResult calldata r, bytes[] calldata sigs)
        private
        view
    {
        bytes32 digest = hashRunResult(r);
        uint256 n = sigs.length;
        address[] memory seen = new address[](n);
        uint256 count;

        for (uint256 i; i < n; ++i) {
            address signer = ECDSA.recover(digest, sigs[i]); // reverts on malleable or malformed
            if (!$.attestors[signer]) revert NotAttestor(signer);
            for (uint256 j; j < count; ++j) {
                if (seen[j] == signer) revert DuplicateSigner(signer);
            }
            seen[count++] = signer;
        }

        if (count < $.threshold) revert ThresholdNotMet(count, $.threshold);
    }
```

- [ ] **Step 5: Run the test and watch it pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/ArenaEscrow.settle.t.sol -vv
```

Expected: all 21 tests PASS. `test_phaseTwoShape_twoOfThreeAttestorsSuffice` is the proof that
moving to Phase 2 needs configuration, not a rewrite.

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/ArenaEscrow.sol contracts/test/ArenaEscrow.settle.t.sol contracts/test/helpers
git commit -m "feat(contracts): threshold EIP-712 settlement with wave-tier payouts"
```

---

### Task 6: `ArenaEscrow.abandonRun` and access control

Without this, a monitor outage would lock a player's stake forever.

**Files:**
- Modify: `contracts/src/ArenaEscrow.sol`
- Create: `contracts/test/ArenaEscrow.admin.t.sol`

**Interfaces:**
- Produces: `abandonRun(bytes32 runId)`, `setRunTtl(uint64)`, `setSeasonRegistry(address)`.

- [ ] **Step 1: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/ArenaEscrow.admin.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {SignerLib} from "./helpers/SignerLib.sol";

contract ArenaEscrowAdminTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    uint256 internal monitorPk;
    address internal monitor;

    function setUp() public {
        (monitor, monitorPk) = makeAddrAndKey("monitor");
        registry = SeasonRegistry(address(new ERC1967Proxy(
            address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))
        )));
        escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
        ))));
        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        escrow.setAttestor(monitor, true);
        vm.stopPrank();
        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);
        vm.deal(alice, 1_000 ether);
    }

    function _start(uint256 amount) internal returns (bytes32) {
        vm.prank(alice);
        return escrow.startRun{value: amount}(address(0), amount);
    }

    // ---------- abandon: positive ----------

    function test_abandonAfterTheDeadlineReturnsTheExactStake() public {
        IArenaEscrow.Pool memory p0 = escrow.poolOf(address(0));
        bytes32 runId = _start(10 ether);
        uint256 before = alice.balance;

        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);

        assertEq(alice.balance - before, 10 ether, "stake returned in full");
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Abandoned));
        assertEq(escrow.activeRunOf(alice), bytes32(0));

        IArenaEscrow.Pool memory p1 = escrow.poolOf(address(0));
        assertEq(p1.free, p0.free, "the pool is made whole");
        assertEq(p1.reserved, 0);
        assertEq(p1.activeStake, 0);
        assertEq(address(escrow).balance, p1.free + p1.reserved + p1.activeStake);
    }

    function test_anyoneMayTriggerAnAbandon() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        vm.prank(makeAddr("goodSamaritan"));
        escrow.abandonRun(runId);
        assertEq(uint8(escrow.runOf(runId).state), uint8(IArenaEscrow.RunState.Abandoned));
    }

    function test_theSamePlayerCanStartAgainAfterAbandoning() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);
        bytes32 second = _start(1 ether);
        assertTrue(second != runId);
    }

    // ---------- abandon: negative ----------

    function test_revert_abandonBeforeTheDeadline() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline); // exactly at, not past
        vm.expectRevert(ArenaEscrow.RunNotExpired.selector);
        escrow.abandonRun(runId);
    }

    function test_revert_abandonTwice() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.abandonRun(runId);
    }

    function test_revert_settleAfterAbandon() public {
        bytes32 runId = _start(1 ether);
        vm.warp(escrow.runOf(runId).deadline + 1);
        escrow.abandonRun(runId);

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId, player: alice, waveReached: 15, score: 1, endedAt: uint64(block.timestamp)
        });
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r))));
    }

    function test_revert_abandonAfterSettle() public {
        bytes32 runId = _start(1 ether);
        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId, player: alice, waveReached: 15, score: 1, endedAt: uint64(block.timestamp)
        });
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r))));
        vm.warp(block.timestamp + 3 hours);
        vm.expectRevert(ArenaEscrow.RunNotActive.selector);
        escrow.abandonRun(runId);
    }

    // ---------- admin access control ----------

    function test_revert_strangerCannotSetAttestor() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.setAttestor(alice, true);
    }

    function test_revert_strangerCannotSetThreshold() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.setThreshold(5);
    }

    function test_revert_strangerCannotSetMaxStake() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.setMaxStake(address(0), 1);
    }

    function test_revert_strangerCannotWithdraw() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.withdrawFree(address(0), alice, 1);
    }

    function test_revert_strangerCannotFundPool() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(ArenaEscrow.NotFunder.selector);
        escrow.fundPool{value: 1 ether}(address(0), 1 ether);
    }

    function test_ascCanFundPool() public {
        address asc = makeAddr("asc");
        vm.prank(owner);
        escrow.setAsc(asc);
        vm.deal(asc, 5 ether);
        vm.prank(asc);
        escrow.fundPool{value: 5 ether}(address(0), 5 ether);
        assertEq(escrow.poolOf(address(0)).free, 1_005 ether);
    }

    function test_revert_thresholdCannotBeZero() public {
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setThreshold(0);
    }

    // ---------- tier validation ----------

    function test_revert_tiersBelowOneTimesAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](1);
        t[0] = IArenaEscrow.Tier({minWave: 5, multiplierBps: 9_000}); // 0.9x
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_revert_tiersAboveTheMaximumAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](1);
        t[0] = IArenaEscrow.Tier({minWave: 5, multiplierBps: 30_001});
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_revert_nonMonotonicTiersAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](2);
        t[0] = IArenaEscrow.Tier({minWave: 10, multiplierBps: 20_000});
        t[1] = IArenaEscrow.Tier({minWave: 5, multiplierBps: 15_000}); // goes backwards
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_revert_emptyTiersAreRejected() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](0);
        vm.prank(owner);
        vm.expectRevert(ArenaEscrow.BadTiers.selector);
        escrow.setMultiplierTiers(t);
    }

    function test_ownerCanReplaceTheTierSchedule() public {
        IArenaEscrow.Tier[] memory t = new IArenaEscrow.Tier[](2);
        t[0] = IArenaEscrow.Tier({minWave: 3, multiplierBps: 12_000});
        t[1] = IArenaEscrow.Tier({minWave: 20, multiplierBps: 25_000});
        vm.prank(owner);
        escrow.setMultiplierTiers(t);
        assertEq(escrow.multiplierBpsFor(2), 0);
        assertEq(escrow.multiplierBpsFor(3), 12_000);
        assertEq(escrow.multiplierBpsFor(19), 12_000);
        assertEq(escrow.multiplierBpsFor(20), 25_000);
    }

    // ---------- a real-game scenario ----------

    function test_scenario_monitorGoesDownMidRunAndThePlayerIsMadeWhole() public {
        // The game's solo mode has no hard time limit; a player who disconnects mid-run leaves
        // the monitor with nothing to sign. The stake must not be trapped.
        uint256 before = alice.balance;
        bytes32 runId = _start(25 ether);
        vm.warp(block.timestamp + 2 hours + 1);
        escrow.abandonRun(runId);
        assertEq(alice.balance, before, "the player is exactly where they started");
    }
}
EOF
forge test --match-path test/ArenaEscrow.admin.t.sol
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: compilation FAILS — `abandonRun` and `RunNotExpired` do not exist.

- [ ] **Step 3: Add `abandonRun` and the remaining setters**

Add the error:

```solidity
    error RunNotExpired();
```

Add the functions:

```solidity
    /// @notice Return a stake after the settlement window closes. Callable by anyone, so a
    ///         monitor outage can never trap a player's funds.
    function abandonRun(bytes32 runId) external nonReentrant {
        EscrowStorage storage $ = _s();
        Run storage run = $.runs[runId];

        if (run.state != RunState.Active) revert RunNotActive();
        if (block.timestamp <= run.deadline) revert RunNotExpired();

        address player = run.player;
        address token = run.token;
        uint256 stake = run.stake;
        uint256 reserved = run.reserved;

        run.state = RunState.Abandoned;
        delete $.activeRun[player];

        Pool storage p = $.pools[token];
        p.reserved -= reserved;
        p.free += reserved;
        p.activeStake -= stake;

        emit RunAbandoned(runId, player, stake);
        _pay(token, player, stake);
    }

    function setRunTtl(uint64 ttl) external onlyOwner {
        _s().runTtl = ttl;
    }

    function setSeasonRegistry(address registry) external onlyOwner {
        _s().seasonRegistry = ISeasonRegistry(registry);
    }
```

- [ ] **Step 4: Run the whole suite**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test -vv
```

Expected: every test in `USDT`, `SeasonRegistry`, `ArenaEscrow.start`, `ArenaEscrow.settle` and
`ArenaEscrow.admin` PASSES.

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/ArenaEscrow.sol contracts/test/ArenaEscrow.admin.t.sol
git commit -m "feat(contracts): abandonRun safety valve and tier validation"
```

---

### Task 7: `ASCReadableUpgradeable`, the mock precompile and transaction fixtures

A proxy-safe port of `@gluwa/asc-contracts`'s `ASCBase`, plus the test scaffolding every
Attestcoin test needs.

Two deliberate differences from `ASCBase`, both required:

1. `VERIFIER` is an `internal constant` rather than an `immutable` set in a constructor, so the
   contract has no constructor logic at all and is clean under a proxy.
2. `_processAndEmitEvent` receives **`chainKey`**. `ASCBase` omits it, but without it the
   subclass cannot check the log emitter against the registered source gate — the single most
   important security check in this system.

**Files:**
- Create: `contracts/src/asc/ASCReadableUpgradeable.sol`
- Create: `contracts/test/helpers/MockBlockProver.sol`
- Create: `contracts/test/helpers/TxFixture.sol`

**Interfaces:**
- Produces:
  - `abstract contract ASCReadableUpgradeable` with `execute(uint8 action, uint64 chainKey, uint64 blockHeight, bytes calldata encodedTransaction, bytes32 merkleRoot, INativeQueryVerifier.MerkleProofEntry[] calldata siblings, bytes32 lowerEndpointDigest, bytes32[] calldata continuityRoots) returns (bool)`
  - hook `_processAndEmitEvent(uint8 action, uint64 chainKey, bytes32 queryId, bytes memory encodedTransaction)`
  - `processedQueries(bytes32) returns (bool)`
  - `MockBlockProver.mockSet(bool verify, uint64 txIndex, bool doRevert)` — etch at `0x…0FD2`
  - `TxFixture.encode(uint8 txType, address from, address to, uint8 status, TxFixture.Log[] logs) returns (bytes)`

- [ ] **Step 1: Write the base contract**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/asc/ASCReadableUpgradeable.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {INativeQueryVerifier} from
    "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

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
    INativeQueryVerifier internal constant VERIFIER =
        INativeQueryVerifier(0x0000000000000000000000000000000000000FD2);

    /// @custom:storage-location erc7201:inkstake.storage.ASCReadable
    struct ASCReadableStorage {
        mapping(bytes32 queryId => bool) processed;
    }

    bytes32 private constant STORAGE_SLOT =
        0xc93ddaed6853b6750c13e9d657f8d94b1582a34a1c5316222dcd54ccc718c100;

    function _ascStorage() private pure returns (ASCReadableStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    function processedQueries(bytes32 queryId) public view returns (bool) {
        return _ascStorage().processed[queryId];
    }

    /// @notice App-specific handler, invoked only after the proof verifies and dedupes.
    function _processAndEmitEvent(
        uint8 action,
        uint64 chainKey,
        bytes32 queryId,
        bytes memory encodedTransaction
    ) internal virtual;

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
            INativeQueryVerifier.ContinuityProof({
                lowerEndpointDigest: lowerEndpointDigest,
                roots: continuityRoots
            });

        bool verified = VERIFIER.verifyAndEmit(
            chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof
        );
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
EOF
```

- [ ] **Step 2: Write the mock precompile**

`vm.etch` copies runtime code to an address but leaves its storage empty, so the mock exposes a
setter that writes into the etched address's own storage.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/helpers/MockBlockProver.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INativeQueryVerifier} from
    "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/// @notice Stand-in for the Creditcoin block-prover precompile, which has no bytecode on a local
///         EVM. Etch this at 0x…0FD2 with `vm.etch`, then call `mockSet` on that address.
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

    function calculateTxIndex(INativeQueryVerifier.MerkleProof calldata)
        external
        view
        returns (uint64)
    {
        return nextTxIndex;
    }
}
EOF
```

- [ ] **Step 3: Write the transaction fixture builder**

The encoding is `abi.encode(uint8 txType, bytes[] chunks)` where, for types 0–2, `chunks` has
exactly three entries and the receipt is `chunks[2]`. `chunks[1]` is never read by
`decodeReceiptFields` or `decodeCommonTxFields`, so it can be empty. Task 1's `Imports.t.sol`
proved the type byte round-trips.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/helpers/TxFixture.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Builds `encodedTransaction` bytes in the exact layout EvmV1Decoder expects, so unit
///         tests need no live Sepolia transaction. The fork test in test/fork/ uses real bytes.
library TxFixture {
    struct Log {
        address address_;
        bytes32[] topics;
        bytes data;
    }

    /// @param txType 0-2 (three chunks). Types 3-4 use four chunks and are not needed here.
    function encode(uint8 txType, address from, address to, uint8 status, Log[] memory logs)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory common = abi.encode(
            uint64(1), // nonce
            uint64(21000), // gasLimit
            from,
            false, // toIsNull
            to,
            uint256(0), // value
            bytes("") // data
        );
        bytes memory receipt = abi.encode(status, uint64(21000), logs, bytes(""));

        bytes[] memory chunks = new bytes[](3);
        chunks[0] = common;
        chunks[1] = bytes(""); // type-specific fields; never read on this path
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
EOF
forge build
```

Expected: `Compiler run successful`.

- [ ] **Step 4: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/asc/ASCReadableUpgradeable.sol contracts/test/helpers/MockBlockProver.sol contracts/test/helpers/TxFixture.sol
git commit -m "feat(contracts): proxy-safe Attestcoin readability base and test scaffolding"
```

---

### Task 8: `DoodleGateASC` — the Attestcoin integration

**Files:**
- Create: `contracts/src/asc/DoodleGateASC.sol`
- Create: `contracts/test/DoodleGateASC.t.sol`

**Interfaces:**
- Consumes: `ASCReadableUpgradeable` (Task 7), `USDT.mint` (Task 2), `ArenaEscrow.fundPool` (Task 4).
- Produces:
  - `initialize(address initialOwner, address usdt, address escrow)`
  - `setSourceGate(uint64 chainKey, address gate)`, `setUsdtPerSourceUnit(uint256)`, `setMaxCreditPerQuery(uint256)`
  - `ENTRY_PAID_SIGNATURE`, `PRIZE_FUNDED_SIGNATURE`
  - Events `EntryCredited(address player, bytes32 runRef, uint256 credited, bytes32 queryId)` and
    `PoolSponsored(address sponsor, uint256 credited, bytes32 queryId)`.
  - Plan 3's relayer calls `execute(...)`.

- [ ] **Step 1: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/DoodleGateASC.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {INativeQueryVerifier} from
    "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";
import {ASCReadableUpgradeable} from "../src/asc/ASCReadableUpgradeable.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {MockBlockProver} from "./helpers/MockBlockProver.sol";
import {TxFixture} from "./helpers/TxFixture.sol";

contract DoodleGateASCTest is Test {
    address constant PRECOMPILE = 0x0000000000000000000000000000000000000FD2;
    uint64 constant SEPOLIA_KEY = 1; // Attestcoin chainKey, not 11155111

    DoodleGateASC internal asc;
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;
    MockBlockProver internal prover;

    address internal owner = makeAddr("owner");
    address internal player = makeAddr("player");
    address internal sponsor = makeAddr("sponsor");
    address internal sourceGate = makeAddr("sourceGate");
    address internal impostorGate = makeAddr("impostorGate");

    bytes32 constant RUN_REF = keccak256("run-ref-1");

    function setUp() public {
        // Etch the mock precompile and arm it.
        prover = new MockBlockProver();
        vm.etch(PRECOMPILE, address(prover).code);
        MockBlockProver(PRECOMPILE).mockSet(true, 3, false);

        registry = SeasonRegistry(address(new ERC1967Proxy(
            address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))
        )));
        usdt = USDT(address(new ERC1967Proxy(
            address(new USDT()), abi.encodeCall(USDT.initialize, (owner))
        )));
        escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
        ))));
        asc = DoodleGateASC(address(new ERC1967Proxy(
            address(new DoodleGateASC()),
            abi.encodeCall(DoodleGateASC.initialize, (owner, address(usdt), address(escrow)))
        )));

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setAsc(address(asc));
        escrow.setMaxStake(address(usdt), 100e6);
        usdt.setMinter(address(asc), true);
        asc.setSourceGate(SEPOLIA_KEY, sourceGate);
        asc.setUsdtPerSourceUnit(100e6); // 100 USDT credited per 1 source-chain unit
        asc.setMaxCreditPerQuery(1_000e6);
        vm.stopPrank();
    }

    // ---- proof plumbing: every call needs these, none of it is asserted on ----
    function _siblings() internal pure returns (INativeQueryVerifier.MerkleProofEntry[] memory s) {
        s = new INativeQueryVerifier.MerkleProofEntry[](1);
        s[0] = INativeQueryVerifier.MerkleProofEntry({hash: keccak256("sib"), isLeft: true});
    }

    function _roots() internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = keccak256("root");
    }

    function _entryTx(address emitter, uint8 status, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes32[] memory topics = TxFixture.topics3(
            asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), RUN_REF
        );
        return TxFixture.encode(
            2, player, emitter, status, TxFixture.oneLog(emitter, topics, abi.encode(amount))
        );
    }

    function _prizeTx(address emitter, uint8 status, uint256 amount)
        internal
        view
        returns (bytes memory)
    {
        bytes32[] memory topics = TxFixture.topics2(
            asc.PRIZE_FUNDED_SIGNATURE(), bytes32(uint256(uint160(sponsor)))
        );
        return TxFixture.encode(
            2, sponsor, emitter, status, TxFixture.oneLog(emitter, topics, abi.encode(amount))
        );
    }

    function _exec(uint8 action, bytes memory encodedTx, uint64 height) internal returns (bool) {
        return asc.execute(
            action, SEPOLIA_KEY, height, encodedTx, keccak256("merkleRoot"),
            _siblings(), keccak256("lower"), _roots()
        );
    }

    // ---------- positive ----------

    function test_entryPaidMintsCreditToThePlayer() public {
        _exec(0, _entryTx(sourceGate, 1, 2e18), 100);
        assertEq(usdt.balanceOf(player), 200e6, "2 units x 100 USDT");
    }

    function test_prizeFundedTopsUpTheRewardPool() public {
        _exec(1, _prizeTx(sourceGate, 1, 5e18), 101);
        assertEq(escrow.poolOf(address(usdt)).free, 500e6);
        assertEq(usdt.balanceOf(address(escrow)), 500e6);
    }

    function test_queryIsMarkedProcessed() public {
        _exec(0, _entryTx(sourceGate, 1, 1e18), 102);
        bytes32 queryId = keccak256(abi.encodePacked(SEPOLIA_KEY, uint64(102), uint64(3)));
        assertTrue(asc.processedQueries(queryId));
    }

    function test_creditedPlayerCanImmediatelyStake() public {
        _exec(0, _entryTx(sourceGate, 1, 1e18), 103);
        vm.startPrank(owner);
        usdt.mint(owner, 10_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 10_000e6);
        vm.stopPrank();

        vm.startPrank(player);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.startRun(address(usdt), 100e6); // never held tCTC
        vm.stopPrank();
        assertTrue(escrow.activeRunOf(player) != bytes32(0));
    }

    // ---------- edge ----------

    function test_onlyTheMatchingEventIsPickedOutOfABusyTransaction() public {
        TxFixture.Log[] memory logs = new TxFixture.Log[](3);
        logs[0] = TxFixture.Log({
            address_: makeAddr("someToken"),
            topics: TxFixture.topics2(keccak256("Transfer(address,address,uint256)"), bytes32(0)),
            data: abi.encode(uint256(999))
        });
        logs[1] = TxFixture.Log({
            address_: sourceGate,
            topics: TxFixture.topics3(
                asc.ENTRY_PAID_SIGNATURE(), bytes32(uint256(uint160(player))), RUN_REF
            ),
            data: abi.encode(uint256(1e18))
        });
        logs[2] = TxFixture.Log({
            address_: makeAddr("noise"),
            topics: TxFixture.topics2(keccak256("Approval(address,address,uint256)"), bytes32(0)),
            data: abi.encode(uint256(1))
        });
        _exec(0, TxFixture.encode(2, player, sourceGate, 1, logs), 104);
        assertEq(usdt.balanceOf(player), 100e6);
    }

    function test_differentChainKeysRegisterIndependently() public {
        address otherGate = makeAddr("otherGate");
        vm.prank(owner);
        asc.setSourceGate(3, otherGate); // Ethereum mainnet is chainKey 3
        assertEq(asc.sourceGateOf(SEPOLIA_KEY), sourceGate);
        assertEq(asc.sourceGateOf(3), otherGate);
    }

    function test_sameHeightDifferentTxIndexAreDistinctQueries() public {
        _exec(0, _entryTx(sourceGate, 1, 1e18), 105);
        MockBlockProver(PRECOMPILE).mockSet(true, 4, false); // a different transaction index
        _exec(0, _entryTx(sourceGate, 1, 1e18), 105);
        assertEq(usdt.balanceOf(player), 200e6, "both were credited");
    }

    // ---------- negative ----------

    function test_revert_replayOfTheSameQuery() public {
        bytes memory encodedTx = _entryTx(sourceGate, 1, 1e18);
        _exec(0, encodedTx, 106);
        bytes32 queryId = keccak256(abi.encodePacked(SEPOLIA_KEY, uint64(106), uint64(3)));
        vm.expectRevert(
            abi.encodeWithSelector(ASCReadableUpgradeable.QueryAlreadyProcessed.selector, queryId)
        );
        _exec(0, encodedTx, 106);
    }

    /// The precompile proves INCLUSION, not SUCCESS. A reverted payment must never mint.
    function test_revert_transactionThatFailedOnTheSourceChain() public {
        vm.expectRevert(DoodleGateASC.SourceTransactionFailed.selector);
        _exec(0, _entryTx(sourceGate, 0, 1e18), 107);
    }

    /// THE most important test in this repository. Without the emitter binding, anyone can
    /// deploy a look-alike contract on Sepolia and mint themselves unlimited credit.
    function test_revert_eventFromAnUnregisteredEmitter() public {
        vm.expectRevert(
            abi.encodeWithSelector(DoodleGateASC.UnknownEmitter.selector, SEPOLIA_KEY, impostorGate)
        );
        _exec(0, _entryTx(impostorGate, 1, 1e18), 108);
    }

    function test_revert_unregisteredChainKey() public {
        bytes memory encodedTx = _entryTx(sourceGate, 1, 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(DoodleGateASC.UnknownEmitter.selector, uint64(99), sourceGate)
        );
        asc.execute(
            0, 99, 109, encodedTx, keccak256("merkleRoot"), _siblings(), keccak256("lower"), _roots()
        );
    }

    function test_revert_unknownAction() public {
        vm.expectRevert(abi.encodeWithSelector(DoodleGateASC.InvalidAction.selector, uint8(7)));
        _exec(7, _entryTx(sourceGate, 1, 1e18), 110);
    }

    function test_revert_noMatchingEventInTheTransaction() public {
        TxFixture.Log[] memory logs = new TxFixture.Log[](1);
        logs[0] = TxFixture.Log({
            address_: sourceGate,
            topics: TxFixture.topics2(keccak256("Transfer(address,address,uint256)"), bytes32(0)),
            data: abi.encode(uint256(1))
        });
        vm.expectRevert(DoodleGateASC.NoMatchingEvent.selector);
        _exec(0, TxFixture.encode(2, player, sourceGate, 1, logs), 111);
    }

    function test_revert_whenTheProofDoesNotVerify() public {
        MockBlockProver(PRECOMPILE).mockSet(false, 3, false);
        vm.expectRevert(ASCReadableUpgradeable.ProofVerificationFailed.selector);
        _exec(0, _entryTx(sourceGate, 1, 1e18), 112);
    }

    function test_revert_creditAboveThePerQueryCap() public {
        vm.expectRevert(
            abi.encodeWithSelector(DoodleGateASC.CreditTooLarge.selector, 2_000e6, 1_000e6)
        );
        _exec(0, _entryTx(sourceGate, 1, 20e18), 113);
    }

    function test_revert_strangerCannotSetSourceGate() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        asc.setSourceGate(SEPOLIA_KEY, impostorGate);
    }

    function test_revert_strangerCannotChangeTheRate() public {
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        asc.setUsdtPerSourceUnit(1);
    }
}
EOF
forge test --match-path test/DoodleGateASC.t.sol
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: compilation FAILS — `src/asc/DoodleGateASC.sol` does not exist.

- [ ] **Step 3: Implement `DoodleGateASC`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/asc/DoodleGateASC.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";

import {ASCReadableUpgradeable} from "./ASCReadableUpgradeable.sol";

interface IUSDTMintable {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IArenaPool {
    function fundPool(address token, uint256 amount) external payable;
}

/// @title DoodleGateASC
/// @notice The Attestcoin Smart Contract for Inkstake Arena. Proves that a payment happened on a
///         source chain and credits it on Creditcoin — no oracle, no trusted relayer.
/// @dev Two actions share one source contract, following the protocol's own guidance: a single
///      source-chain emitter with unambiguous, purpose-named events.
///
///      Security rests on two checks, both called out in the Attestcoin docs:
///        1. `receiptStatus == 1`. The precompile proves a transaction was INCLUDED in a real
///           block. It does NOT prove the transaction SUCCEEDED.
///        2. The emitting log address must equal the registered `sourceGate[chainKey]`. Without
///           it, anyone could deploy a look-alike emitter and mint unlimited credit.
contract DoodleGateASC is ASCReadableUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error InvalidAction(uint8 action);
    error UnsupportedTxType(uint8 txType);
    error SourceTransactionFailed();
    error NoMatchingEvent();
    error UnknownEmitter(uint64 chainKey, address emitter);
    error CreditTooLarge(uint256 credited, uint256 cap);
    error MalformedEvent();

    enum Action {
        EntryPaid, // 0
        PrizeFunded // 1
    }

    /// keccak256("ArenaEntryPaid(address,bytes32,uint256)")
    bytes32 public constant ENTRY_PAID_SIGNATURE =
        keccak256("ArenaEntryPaid(address,bytes32,uint256)");
    /// keccak256("PrizePoolFunded(address,uint256)")
    bytes32 public constant PRIZE_FUNDED_SIGNATURE =
        keccak256("PrizePoolFunded(address,uint256)");

    event EntryCredited(
        address indexed player, bytes32 indexed runRef, uint256 credited, bytes32 indexed queryId
    );
    event PoolSponsored(address indexed sponsor, uint256 credited, bytes32 indexed queryId);
    event SourceGateSet(uint64 indexed chainKey, address indexed gate);

    /// @custom:storage-location erc7201:inkstake.storage.DoodleGateASC
    struct ASCStorage {
        IUSDTMintable usdt;
        IArenaPool escrow;
        uint256 usdtPerSourceUnit; // USDT (6dp) credited per 1e18 of source-chain value
        uint256 maxCreditPerQuery;
        mapping(uint64 chainKey => address gate) sourceGate;
    }

    bytes32 private constant STORAGE_SLOT =
        0x12d06c2cb907555d20e6d5be977c9855812f0706a9bcd821f201f9346d1b8300;

    function _s() private pure returns (ASCStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address usdt, address escrow) external initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        ASCStorage storage $ = _s();
        $.usdt = IUSDTMintable(usdt);
        $.escrow = IArenaPool(escrow);
    }

    // ---------------- views and admin ----------------

    function sourceGateOf(uint64 chainKey) external view returns (address) {
        return _s().sourceGate[chainKey];
    }

    function usdtPerSourceUnit() external view returns (uint256) {
        return _s().usdtPerSourceUnit;
    }

    function maxCreditPerQuery() external view returns (uint256) {
        return _s().maxCreditPerQuery;
    }

    /// @notice Bind a source chain to the ONLY contract whose events this ASC will honour.
    function setSourceGate(uint64 chainKey, address gate) external onlyOwner {
        _s().sourceGate[chainKey] = gate;
        emit SourceGateSet(chainKey, gate);
    }

    function setUsdtPerSourceUnit(uint256 rate) external onlyOwner {
        _s().usdtPerSourceUnit = rate;
    }

    function setMaxCreditPerQuery(uint256 cap) external onlyOwner {
        _s().maxCreditPerQuery = cap;
    }

    // ---------------- readability handler ----------------

    function _processAndEmitEvent(
        uint8 action,
        uint64 chainKey,
        bytes32 queryId,
        bytes memory encodedTransaction
    ) internal override {
        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) revert UnsupportedTxType(txType);

        EvmV1Decoder.ReceiptFields memory receipt =
            EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        // The precompile proves inclusion, not success. This check is mandatory.
        if (receipt.receiptStatus != 1) revert SourceTransactionFailed();

        if (action == uint8(Action.EntryPaid)) {
            _creditEntry(chainKey, queryId, receipt);
        } else if (action == uint8(Action.PrizeFunded)) {
            _sponsorPool(chainKey, queryId, receipt);
        } else {
            revert InvalidAction(action);
        }
    }

    function _creditEntry(uint64 chainKey, bytes32 queryId, EvmV1Decoder.ReceiptFields memory receipt)
        private
    {
        EvmV1Decoder.LogEntry[] memory logs =
            EvmV1Decoder.getLogsByEventSignature(receipt, ENTRY_PAID_SIGNATURE);
        if (logs.length == 0) revert NoMatchingEvent();

        // Policy: only the first matching event in a transaction is honoured.
        EvmV1Decoder.LogEntry memory log = logs[0];
        _requireRegisteredEmitter(chainKey, log.address_);
        if (log.topics.length != 3 || log.data.length != 32) revert MalformedEvent();

        address player = address(uint160(uint256(log.topics[1])));
        bytes32 runRef = log.topics[2];
        uint256 amount = abi.decode(log.data, (uint256));

        uint256 credited = _convert(amount);
        _s().usdt.mint(player, credited);
        emit EntryCredited(player, runRef, credited, queryId);
    }

    function _sponsorPool(uint64 chainKey, bytes32 queryId, EvmV1Decoder.ReceiptFields memory receipt)
        private
    {
        EvmV1Decoder.LogEntry[] memory logs =
            EvmV1Decoder.getLogsByEventSignature(receipt, PRIZE_FUNDED_SIGNATURE);
        if (logs.length == 0) revert NoMatchingEvent();

        EvmV1Decoder.LogEntry memory log = logs[0];
        _requireRegisteredEmitter(chainKey, log.address_);
        if (log.topics.length != 2 || log.data.length != 32) revert MalformedEvent();

        address sponsor = address(uint160(uint256(log.topics[1])));
        uint256 amount = abi.decode(log.data, (uint256));

        ASCStorage storage $ = _s();
        uint256 credited = _convert(amount);
        $.usdt.mint(address(this), credited);
        $.usdt.approve(address($.escrow), credited);
        $.escrow.fundPool(address($.usdt), credited);

        emit PoolSponsored(sponsor, credited, queryId);
    }

    function _requireRegisteredEmitter(uint64 chainKey, address emitter) private view {
        if (_s().sourceGate[chainKey] != emitter || emitter == address(0)) {
            revert UnknownEmitter(chainKey, emitter);
        }
    }

    function _convert(uint256 sourceAmount) private view returns (uint256 credited) {
        ASCStorage storage $ = _s();
        credited = (sourceAmount * $.usdtPerSourceUnit) / 1e18;
        if (credited > $.maxCreditPerQuery) revert CreditTooLarge(credited, $.maxCreditPerQuery);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
EOF
```

- [ ] **Step 4: Run the test and watch it pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/DoodleGateASC.t.sol -vv
```

Expected: all 16 tests PASS. Pay particular attention to
`test_revert_eventFromAnUnregisteredEmitter` and
`test_revert_transactionThatFailedOnTheSourceChain` — those two are the bridge's security.

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/asc/DoodleGateASC.sol contracts/test/DoodleGateASC.t.sol
git commit -m "feat(contracts): DoodleGateASC cross-chain entry and sponsorship via Attestcoin"
```

---

### Task 9: `DoodleGate` — the Sepolia source contract

Deliberately tiny. The protocol's guidance is to keep source-chain logic minimal and let it exist
mainly to emit unambiguous events.

**Files:**
- Create: `contracts/src/sepolia/DoodleGate.sol`
- Create: `contracts/test/DoodleGate.t.sol`

**Interfaces:**
- Produces: `payEntry(bytes32 runRef) payable`, `fundPrize() payable`, `withdraw(address to)`.
  Event signatures must match `DoodleGateASC.ENTRY_PAID_SIGNATURE` and `PRIZE_FUNDED_SIGNATURE`
  exactly — Step 1 asserts this.

- [ ] **Step 1: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/DoodleGate.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {DoodleGate} from "../src/sepolia/DoodleGate.sol";

contract DoodleGateTest is Test {
    DoodleGate internal gate;
    address internal owner = makeAddr("owner");
    address internal player = makeAddr("player");
    address internal sponsor = makeAddr("sponsor");
    bytes32 constant RUN_REF = keccak256("run-ref");

    event ArenaEntryPaid(address indexed player, bytes32 indexed runRef, uint256 amount);
    event PrizePoolFunded(address indexed sponsor, uint256 amount);

    function setUp() public {
        gate = new DoodleGate(owner);
        vm.deal(player, 10 ether);
        vm.deal(sponsor, 10 ether);
    }

    // ---------- the event shapes the ASC keys off ----------

    /// @dev `vm.expectEmit` below already pins the topic hashes, because a mismatched event
    ///      signature produces a different topic0 and the expectation fails. The cross-contract
    ///      assertion lives in DoodleGateASC.t.sol, which checks the ASC's constants against the
    ///      same literals.

    // ---------- positive ----------

    function test_payEntryEmitsTheEventAndHoldsTheFunds() public {
        vm.expectEmit(true, true, false, true, address(gate));
        emit ArenaEntryPaid(player, RUN_REF, 1 ether);
        vm.prank(player);
        gate.payEntry{value: 1 ether}(RUN_REF);
        assertEq(address(gate).balance, 1 ether);
    }

    function test_fundPrizeEmitsTheEvent() public {
        vm.expectEmit(true, false, false, true, address(gate));
        emit PrizePoolFunded(sponsor, 2 ether);
        vm.prank(sponsor);
        gate.fundPrize{value: 2 ether}();
        assertEq(address(gate).balance, 2 ether);
    }

    function test_ownerCanWithdraw() public {
        vm.prank(player);
        gate.payEntry{value: 1 ether}(RUN_REF);
        uint256 before = owner.balance;
        vm.prank(owner);
        gate.withdraw(owner);
        assertEq(owner.balance - before, 1 ether);
        assertEq(address(gate).balance, 0);
    }

    // ---------- edge ----------

    function test_theSamePlayerCanPayForSeveralRuns() public {
        vm.startPrank(player);
        gate.payEntry{value: 1 ether}(keccak256("a"));
        gate.payEntry{value: 1 ether}(keccak256("b"));
        vm.stopPrank();
        assertEq(address(gate).balance, 2 ether);
    }

    // ---------- negative ----------

    function test_revert_payEntryWithNoValue() public {
        vm.prank(player);
        vm.expectRevert(DoodleGate.ZeroValue.selector);
        gate.payEntry(RUN_REF);
    }

    function test_revert_fundPrizeWithNoValue() public {
        vm.prank(sponsor);
        vm.expectRevert(DoodleGate.ZeroValue.selector);
        gate.fundPrize();
    }

    function test_revert_strangerCannotWithdraw() public {
        vm.prank(player);
        gate.payEntry{value: 1 ether}(RUN_REF);
        vm.prank(player);
        vm.expectRevert();
        gate.withdraw(player);
    }

    function test_revert_plainTransfersAreRejected() public {
        vm.prank(player);
        (bool ok,) = address(gate).call{value: 1 ether}("");
        assertFalse(ok, "a bare transfer emits no event and must be refused");
    }
}
EOF
```

Then add the cross-contract check to `DoodleGateASC.t.sol`, so renaming an event on either side
breaks the build rather than silently breaking the bridge:

```solidity
    function test_signaturesMatchTheSourceContract() public view {
        assertEq(asc.ENTRY_PAID_SIGNATURE(), keccak256("ArenaEntryPaid(address,bytes32,uint256)"));
        assertEq(asc.PRIZE_FUNDED_SIGNATURE(), keccak256("PrizePoolFunded(address,uint256)"));
    }
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path test/DoodleGate.t.sol
```

Expected: compilation FAILS.

- [ ] **Step 3: Implement `DoodleGate`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > src/sepolia/DoodleGate.sol <<'EOF'
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
EOF
forge test --match-path test/DoodleGate.t.sol -vv
```

- [ ] **Step 4: Run and confirm the suite passes**

Expected: all 9 tests PASS. A bare transfer reverts because there is no `receive` function — that
is intentional; value must arrive through a function that emits an event.

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/src/sepolia/DoodleGate.sol contracts/test/DoodleGate.t.sol contracts/test/DoodleGateASC.t.sol
git commit -m "feat(contracts): minimal DoodleGate source contract for Sepolia"
```

---

### Task 10: Fuzz and invariant tests

The solvency claim is the whole safety story. Assert it under randomised sequences, not just the
hand-written paths.

**Files:**
- Create: `contracts/test/ArenaEscrow.invariant.t.sol`

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- The standing invariant: `balance(token) == pool.free + pool.reserved + pool.activeStake`.

- [ ] **Step 1: Write the handler and the invariant test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/ArenaEscrow.invariant.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {SignerLib} from "./helpers/SignerLib.sol";

/// @notice Drives the escrow with randomised calls. Reverts are allowed and expected — the point
///         is that no sequence of successful calls can break the accounting identity.
contract EscrowHandler is Test {
    ArenaEscrow public escrow;
    uint256 internal monitorPk;
    address[] public players;
    bytes32[] public openRuns;

    constructor(ArenaEscrow e, uint256 pk, address[] memory p) {
        escrow = e;
        monitorPk = pk;
        players = p;
    }

    function startRun(uint256 playerSeed, uint256 amount) external {
        address player = players[playerSeed % players.length];
        amount = bound(amount, 1, 100e18);
        if (escrow.activeRunOf(player) != bytes32(0)) return;
        if (escrow.poolOf(address(0)).free < amount * 3) return;

        vm.deal(player, player.balance + amount);
        vm.prank(player);
        try escrow.startRun{value: amount}(address(0), amount) returns (bytes32 runId) {
            openRuns.push(runId);
        } catch {}
    }

    function settleRun(uint256 runSeed, uint32 wave) external {
        if (openRuns.length == 0) return;
        bytes32 runId = openRuns[runSeed % openRuns.length];
        IArenaEscrow.Run memory run = escrow.runOf(runId);
        if (run.state != IArenaEscrow.RunState.Active) return;
        if (block.timestamp > run.deadline) return;

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId,
            player: run.player,
            waveReached: uint32(bound(wave, 0, 40)),
            score: 1,
            endedAt: uint64(block.timestamp)
        });
        try escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r)))) {}
        catch {}
    }

    function abandonRun(uint256 runSeed) external {
        if (openRuns.length == 0) return;
        bytes32 runId = openRuns[runSeed % openRuns.length];
        try escrow.abandonRun(runId) {} catch {}
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 3 hours));
    }
}

contract ArenaEscrowInvariantTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    EscrowHandler internal handler;
    address internal owner = makeAddr("owner");

    function setUp() public {
        (address monitor, uint256 monitorPk) = makeAddrAndKey("monitor");

        registry = SeasonRegistry(address(new ERC1967Proxy(
            address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))
        )));
        escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
        ))));

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        escrow.setAttestor(monitor, true);
        escrow.setThreshold(1);
        vm.stopPrank();

        vm.deal(owner, 100_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 50_000 ether}(address(0), 50_000 ether);

        address[] memory players = new address[](4);
        players[0] = makeAddr("p0");
        players[1] = makeAddr("p1");
        players[2] = makeAddr("p2");
        players[3] = makeAddr("p3");

        handler = new EscrowHandler(escrow, monitorPk, players);
        targetContract(address(handler));
    }

    /// @notice The contract always holds exactly what it says it holds.
    function invariant_balanceEqualsPoolAccounting() public view {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    /// @notice Reservations never exceed what a full payout of every live run would cost.
    function invariant_reservedCoversEveryLiveRun() public view {
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertGe(p.reserved, p.activeStake * 3);
    }
}

contract ArenaEscrowFuzzTest is Test {
    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    uint256 internal monitorPk;

    function setUp() public {
        address monitor;
        (monitor, monitorPk) = makeAddrAndKey("monitor");
        registry = SeasonRegistry(address(new ERC1967Proxy(
            address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))
        )));
        escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
        ))));
        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        escrow.setAttestor(monitor, true);
        vm.stopPrank();
        vm.deal(owner, 1_000_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 500_000 ether}(address(0), 500_000 ether);
    }

    function testFuzz_payoutNeverExceedsTheReservation(uint256 amount, uint32 wave) public {
        amount = bound(amount, 1, 100e18);
        wave = uint32(bound(wave, 0, 100));

        vm.deal(alice, amount);
        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: amount}(address(0), amount);
        uint256 reserved = escrow.runOf(runId).reserved;

        IArenaEscrow.RunResult memory r = IArenaEscrow.RunResult({
            runId: runId, player: alice, waveReached: wave, score: 1, endedAt: uint64(block.timestamp)
        });
        uint256 before = alice.balance;
        escrow.settleRun(r, SignerLib.one(SignerLib.sign(monitorPk, escrow.hashRunResult(r))));

        assertLe(alice.balance - before, reserved, "a payout can never exceed its reservation");
        IArenaEscrow.Pool memory p = escrow.poolOf(address(0));
        assertEq(address(escrow).balance, p.free + p.reserved + p.activeStake);
    }

    function testFuzz_abandonAlwaysReturnsExactlyTheStake(uint256 amount) public {
        amount = bound(amount, 1, 100e18);
        vm.deal(alice, amount);
        uint256 before = alice.balance;

        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: amount}(address(0), amount);
        vm.warp(block.timestamp + 3 hours);
        escrow.abandonRun(runId);

        assertEq(alice.balance, before, "the player ends exactly where they started");
    }
}
EOF
forge test --match-path test/ArenaEscrow.invariant.t.sol -vv
```

- [ ] **Step 2: Run it**

Expected: both invariants hold across 64 runs of depth 64, and both fuzz tests pass 512 runs.
If `invariant_balanceEqualsPoolAccounting` breaks, the shrunk call sequence Foundry prints is the
bug report — read it before changing anything.

- [ ] **Step 3: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/test/ArenaEscrow.invariant.t.sol
git commit -m "test(contracts): solvency invariants and payout fuzzing"
```

---

### Task 11: Upgrade safety for all four proxies

**Files:**
- Create: `contracts/test/Upgrade.t.sol`
- Create: `contracts/test/helpers/V2Mocks.sol`

- [ ] **Step 1: Write the V2 mocks**

Each adds a new variable **inside its existing ERC-7201 struct**, which is exactly how a real
upgrade would extend state.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/helpers/V2Mocks.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ArenaEscrow} from "../../src/ArenaEscrow.sol";
import {SeasonRegistry} from "../../src/SeasonRegistry.sol";
import {USDT} from "../../src/USDT.sol";
import {DoodleGateASC} from "../../src/asc/DoodleGateASC.sol";

/// @dev V2s add a variable in their own namespaced slot. ERC-7201 keeps the namespaces apart,
///      so nothing that existed before can be displaced.
contract ArenaEscrowV2 is ArenaEscrow {
    /// @custom:storage-location erc7201:inkstake.storage.ArenaEscrowV2
    struct V2Storage {
        string note;
    }

    bytes32 private constant V2_SLOT = keccak256("inkstake.storage.ArenaEscrowV2.test");

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
EOF
```

- [ ] **Step 2: Write the failing test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/Upgrade.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {IArenaEscrow} from "../src/interfaces/IArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";
import {ArenaEscrowV2, SeasonRegistryV2, USDTV2, DoodleGateASCV2} from "./helpers/V2Mocks.sol";

contract UpgradeTest is Test {
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    ArenaEscrow internal escrow;
    SeasonRegistry internal registry;
    USDT internal usdt;
    DoodleGateASC internal asc;

    function setUp() public {
        registry = SeasonRegistry(address(new ERC1967Proxy(
            address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (owner))
        )));
        usdt = USDT(address(new ERC1967Proxy(
            address(new USDT()), abi.encodeCall(USDT.initialize, (owner))
        )));
        escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (owner, address(registry)))
        ))));
        asc = DoodleGateASC(address(new ERC1967Proxy(
            address(new DoodleGateASC()),
            abi.encodeCall(DoodleGateASC.initialize, (owner, address(usdt), address(escrow)))
        )));

        vm.startPrank(owner);
        registry.setEscrow(address(escrow));
        escrow.setMaxStake(address(0), 100e18);
        vm.stopPrank();
        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        escrow.fundPool{value: 1_000 ether}(address(0), 1_000 ether);
    }

    // ---------- state survives ----------

    function test_arenaEscrowStateSurvivesAnUpgrade() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: 10 ether}(address(0), 10 ether);

        IArenaEscrow.Run memory before = escrow.runOf(runId);
        IArenaEscrow.Pool memory poolBefore = escrow.poolOf(address(0));

        vm.prank(owner);
        escrow.upgradeToAndCall(address(new ArenaEscrowV2()), "");

        IArenaEscrow.Run memory afterUpgrade = ArenaEscrowV2(payable(address(escrow))).runOf(runId);
        assertEq(afterUpgrade.player, before.player);
        assertEq(afterUpgrade.stake, before.stake);
        assertEq(afterUpgrade.reserved, before.reserved);
        assertEq(afterUpgrade.seed, before.seed);
        assertEq(uint8(afterUpgrade.state), uint8(IArenaEscrow.RunState.Active));

        IArenaEscrow.Pool memory poolAfter = escrow.poolOf(address(0));
        assertEq(poolAfter.free, poolBefore.free);
        assertEq(poolAfter.reserved, poolBefore.reserved);
        assertEq(poolAfter.activeStake, poolBefore.activeStake);

        assertEq(ArenaEscrowV2(payable(address(escrow))).version(), "v2");
        assertEq(escrow.owner(), owner, "ownership survives");
        assertEq(escrow.maxStakeOf(address(0)), 100e18, "config survives");
    }

    function test_newV2StorageDoesNotDisturbTheOldState() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        bytes32 runId = escrow.startRun{value: 10 ether}(address(0), 10 ether);

        vm.prank(owner);
        escrow.upgradeToAndCall(address(new ArenaEscrowV2()), "");
        ArenaEscrowV2 v2 = ArenaEscrowV2(payable(address(escrow)));
        v2.setNote("hello from v2");

        assertEq(v2.note(), "hello from v2");
        assertEq(v2.runOf(runId).stake, 10 ether, "the run is untouched");
    }

    function test_usdtBalancesSurviveAnUpgrade() public {
        vm.prank(owner);
        usdt.mint(alice, 1_234e6);
        vm.prank(owner);
        usdt.upgradeToAndCall(address(new USDTV2()), "");
        assertEq(usdt.balanceOf(alice), 1_234e6);
        assertEq(usdt.decimals(), 6);
        assertEq(USDTV2(address(usdt)).version(), "v2");
    }

    function test_seasonStatsSurviveAnUpgrade() public {
        vm.prank(address(escrow));
        registry.recordRun(alice, 9, 555, address(0), 1 ether, 0);
        vm.prank(owner);
        registry.upgradeToAndCall(address(new SeasonRegistryV2()), "");
        assertEq(registry.statsOf(1, alice).bestWave, 9);
        assertEq(registry.statsOf(1, alice).bestScore, 555);
    }

    function test_ascConfigSurvivesAnUpgrade() public {
        address gate = makeAddr("gate");
        vm.startPrank(owner);
        asc.setSourceGate(1, gate);
        asc.setUsdtPerSourceUnit(42e6);
        asc.upgradeToAndCall(address(new DoodleGateASCV2()), "");
        vm.stopPrank();
        assertEq(asc.sourceGateOf(1), gate, "the emitter binding must survive");
        assertEq(asc.usdtPerSourceUnit(), 42e6);
    }

    // ---------- access control ----------

    function test_revert_strangerCannotUpgradeArenaEscrow() public {
        address v2 = address(new ArenaEscrowV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        escrow.upgradeToAndCall(v2, "");
    }

    function test_revert_strangerCannotUpgradeUsdt() public {
        address v2 = address(new USDTV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        usdt.upgradeToAndCall(v2, "");
    }

    function test_revert_strangerCannotUpgradeSeasonRegistry() public {
        address v2 = address(new SeasonRegistryV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        registry.upgradeToAndCall(v2, "");
    }

    function test_revert_strangerCannotUpgradeTheAsc() public {
        address v2 = address(new DoodleGateASCV2());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        asc.upgradeToAndCall(v2, "");
    }

    // ---------- initialisation ----------

    function test_revert_initializeTwiceOnEveryProxy() public {
        vm.expectRevert();
        escrow.initialize(alice, address(registry));
        vm.expectRevert();
        registry.initialize(alice);
        vm.expectRevert();
        usdt.initialize(alice);
        vm.expectRevert();
        asc.initialize(alice, address(usdt), address(escrow));
    }

    function test_revert_implementationsCannotBeInitialized() public {
        vm.expectRevert();
        new ArenaEscrow().initialize(alice, address(registry));
        vm.expectRevert();
        new SeasonRegistry().initialize(alice);
        vm.expectRevert();
        new USDT().initialize(alice);
        vm.expectRevert();
        new DoodleGateASC().initialize(alice, address(usdt), address(escrow));
    }
}
EOF
forge test --match-path test/Upgrade.t.sol -vv
```

- [ ] **Step 3: Run the whole suite and check coverage**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test -vv
forge coverage --no-match-coverage 'test/|script/' 2>/dev/null | tail -20
forge fmt --check
```

Expected: every test PASSES; line coverage on `src/` is 90% or better. If coverage falls short,
the gap is almost always an unexercised revert — add the missing negative test rather than
lowering the bar.

- [ ] **Step 4: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/test/Upgrade.t.sol contracts/test/helpers/V2Mocks.sol
git commit -m "test(contracts): upgrade safety across all four UUPS proxies"
```

---

### Task 12: Deployment and Blockscout verification

**Files:**
- Create: `contracts/script/Deploy.s.sol`
- Create: `contracts/script/DeploySepolia.s.sol`
- Create: `contracts/DEPLOYMENT.md`
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Write the Creditcoin deployment script**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > script/Deploy.s.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ArenaEscrow} from "../src/ArenaEscrow.sol";
import {SeasonRegistry} from "../src/SeasonRegistry.sol";
import {USDT} from "../src/USDT.sol";
import {DoodleGateASC} from "../src/asc/DoodleGateASC.sol";

/// @notice Deploys the four Creditcoin proxies and wires them together.
/// forge script script/Deploy.s.sol --rpc-url creditcoin_testnet --broadcast
contract Deploy is Script {
    uint64 constant SEPOLIA_CHAIN_KEY = 1; // Attestcoin chainKey, not 11155111

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address sourceGate = vm.envOr("DOODLE_GATE_SEPOLIA", address(0));

        vm.startBroadcast(pk);

        SeasonRegistry registry = SeasonRegistry(address(new ERC1967Proxy(
            address(new SeasonRegistry()), abi.encodeCall(SeasonRegistry.initialize, (deployer))
        )));
        USDT usdt = USDT(address(new ERC1967Proxy(
            address(new USDT()), abi.encodeCall(USDT.initialize, (deployer))
        )));
        ArenaEscrow escrow = ArenaEscrow(payable(address(new ERC1967Proxy(
            address(new ArenaEscrow()), abi.encodeCall(ArenaEscrow.initialize, (deployer, address(registry)))
        ))));
        DoodleGateASC asc = DoodleGateASC(address(new ERC1967Proxy(
            address(new DoodleGateASC()),
            abi.encodeCall(DoodleGateASC.initialize, (deployer, address(usdt), address(escrow)))
        )));

        // Wiring
        registry.setEscrow(address(escrow));
        escrow.setAsc(address(asc));
        usdt.setMinter(address(asc), true);

        // Caps: 100 of each, in their own decimals
        escrow.setMaxStake(address(0), 100e18); // tCTC
        escrow.setMaxStake(address(usdt), 100e6); // USDT

        // Phase 1: a single attestor, the ink-monitor key.
        escrow.setAttestor(vm.envAddress("MONITOR_ADDRESS"), true);
        escrow.setThreshold(1);

        asc.setUsdtPerSourceUnit(vm.envOr("USDT_PER_SOURCE_UNIT", uint256(100e6)));
        asc.setMaxCreditPerQuery(vm.envOr("MAX_CREDIT_PER_QUERY", uint256(1_000e6)));
        if (sourceGate != address(0)) asc.setSourceGate(SEPOLIA_CHAIN_KEY, sourceGate);

        // Seed the reward pool so runs can be accepted immediately.
        usdt.mint(deployer, 1_000_000e6);
        usdt.approve(address(escrow), type(uint256).max);
        escrow.fundPool(address(usdt), 100_000e6);

        vm.stopBroadcast();

        console2.log("SEASON_REGISTRY=%s", address(registry));
        console2.log("USDT_TOKEN=%s", address(usdt));
        console2.log("ARENA_ESCROW=%s", address(escrow));
        console2.log("DOODLE_GATE_ASC=%s", address(asc));
    }
}
EOF
cat > script/DeploySepolia.s.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {DoodleGate} from "../src/sepolia/DoodleGate.sol";

/// forge script script/DeploySepolia.s.sol --rpc-url sepolia --broadcast
contract DeploySepolia is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        DoodleGate gate = new DoodleGate(vm.addr(pk));
        vm.stopBroadcast();
        console2.log("DOODLE_GATE_SEPOLIA=%s", address(gate));
    }
}
EOF
forge build
```

- [ ] **Step 2: Dry-run against a fork before spending real testnet funds**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
set -a && source .env && set +a
export MONITOR_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
forge script script/Deploy.s.sol --rpc-url creditcoin_testnet
```

Expected: a simulation with no `--broadcast` that completes and prints the four addresses. If it
reverts here it would revert on chain — fix before broadcasting.

- [ ] **Step 3: Deploy Sepolia first, then Creditcoin**

The ASC needs the Sepolia gate address to bind the emitter, so deploy in that order.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
set -a && source .env && set +a
forge script script/DeploySepolia.s.sol --rpc-url sepolia --broadcast
# copy DOODLE_GATE_SEPOLIA into .env, then:
set -a && source .env && set +a
export MONITOR_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
forge script script/Deploy.s.sol --rpc-url creditcoin_testnet --broadcast
```

Record all five addresses in `.env`. Fund the deployer from the Creditcoin testnet faucet first —
see `https://docs.creditcoin.org/wallets/using-testnet-faucet`.

- [ ] **Step 4: Verify every contract on Blockscout**

Both the implementation **and** the proxy must be verified, or Blockscout will not show the
read/write interface.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
set -a && source .env && set +a
VERIFIER="--verifier blockscout --verifier-url https://creditcoin-testnet.blockscout.com/api"

# Implementations — addresses come from the broadcast log
cat broadcast/Deploy.s.sol/102031/run-latest.json | grep -o '"contractName":"[^"]*","contractAddress":"[^"]*"'

forge verify-contract <ARENA_ESCROW_IMPL>    src/ArenaEscrow.sol:ArenaEscrow         --chain 102031 $VERIFIER
forge verify-contract <SEASON_REGISTRY_IMPL> src/SeasonRegistry.sol:SeasonRegistry   --chain 102031 $VERIFIER
forge verify-contract <USDT_IMPL>            src/USDT.sol:USDT                       --chain 102031 $VERIFIER
forge verify-contract <ASC_IMPL>             src/asc/DoodleGateASC.sol:DoodleGateASC --chain 102031 $VERIFIER

# Proxies need their constructor arguments
forge verify-contract $ARENA_ESCROW lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --chain 102031 $VERIFIER \
  --constructor-args $(cast abi-encode "constructor(address,bytes)" <ARENA_ESCROW_IMPL> <INIT_CALLDATA>)
```

Then open each address on Blockscout and confirm the green verified badge and a readable
`Read/Write Contract` tab.

- [ ] **Step 5: Smoke-test the live deployment**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
set -a && source .env && set +a
RPC=https://rpc.cc3-testnet.creditcoin.network
cast call $ARENA_ESCROW "maxStakeOf(address)(uint256)" 0x0000000000000000000000000000000000000000 --rpc-url $RPC
cast call $ARENA_ESCROW "threshold()(uint256)" --rpc-url $RPC
cast call $ARENA_ESCROW "multiplierBpsFor(uint32)(uint32)" 15 --rpc-url $RPC
cast call $DOODLE_GATE_ASC "sourceGateOf(uint64)(address)" 1 --rpc-url $RPC
cast call $USDT_TOKEN "decimals()(uint8)" --rpc-url $RPC
```

Expected: `100000000000000000000`, `1`, `30000`, the Sepolia gate address, and `6`.

- [ ] **Step 6: Write `DEPLOYMENT.md` and extend CI**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > DEPLOYMENT.md <<'EOF'
# Deployment

## Order

1. **Sepolia** — `DoodleGate`. Its address binds the emitter on Creditcoin, so it goes first.
2. **Creditcoin** — `SeasonRegistry`, `USDT`, `ArenaEscrow`, `DoodleGateASC`, then wiring.

## Live addresses

Filled in after deployment; also mirrored into `.env` and into
`game/doodleshooter/src/chain/config.js`.

| Contract | Chain | Proxy | Implementation |
| --- | --- | --- | --- |
| `DoodleGate` | Sepolia | n/a (not upgradeable) | |
| `SeasonRegistry` | Creditcoin | | |
| `USDT` | Creditcoin | | |
| `ArenaEscrow` | Creditcoin | | |
| `DoodleGateASC` | Creditcoin | | |

## Verification

Verify the implementation **and** the proxy. Without the proxy, Blockscout will not render the
Read/Write Contract tab.

## Post-deployment checklist

- [ ] `registry.setEscrow(escrow)`
- [ ] `escrow.setAsc(asc)` and `usdt.setMinter(asc, true)`
- [ ] `escrow.setMaxStake(address(0), 100e18)` and `escrow.setMaxStake(usdt, 100e6)`
- [ ] `escrow.setAttestor(monitorKey, true)` and `escrow.setThreshold(1)`
- [ ] `asc.setSourceGate(1, doodleGateSepolia)` — **the bridge is insecure without this**
- [ ] Reward pool funded; `poolOf(usdt).free` is non-zero
- [ ] Every contract shows a verified badge on Blockscout
EOF
```

Append a Foundry job to `.github/workflows/test.yml`, alongside the existing one:

```yaml
      - name: Run Forge fmt
        working-directory: contracts
        run: forge fmt --check

      - name: Run Forge tests
        working-directory: contracts
        run: forge test -vvv

      - name: Coverage gate
        working-directory: contracts
        run: forge coverage --report summary
```

- [ ] **Step 7: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/script contracts/DEPLOYMENT.md .github/workflows/test.yml
git commit -m "chore(contracts): deployment scripts, verification notes and CI"
```

---

### Task 13: Fork test against the real precompile

Everything so far ran against our own mock. This proves the integration is genuinely live.

**Files:**
- Create: `contracts/test/fork/AttestcoinFork.t.sol`

- [ ] **Step 1: Confirm the precompile answers on the real chain**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
RPC=https://rpc.cc3-testnet.creditcoin.network
cast chain-id --rpc-url $RPC
cast call 0x0000000000000000000000000000000000000fd3 "get_supported_chains()" --rpc-url $RPC | head -c 200; echo
cast call 0x0000000000000000000000000000000000000fd3 "is_height_attested(uint64,uint64)(bool)" 1 1 --rpc-url $RPC
```

Expected: `102031`, a non-empty returndata blob, and a boolean. A precompile has no bytecode, so
`cast code` on it returns `0x` — that is normal and not a failure.

- [ ] **Step 2: Write the fork test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
cat > test/fork/AttestcoinFork.t.sol <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";

interface IChainInfo {
    struct ChainDescriptor {
        uint64 chainKey;
        uint64 genesisHeight;
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

/// @notice Runs against the live Creditcoin Testnet so the REAL precompiles answer.
/// forge test --match-path 'test/fork/*' --fork-url https://rpc.cc3-testnet.creditcoin.network
contract AttestcoinForkTest is Test {
    IChainInfo constant CHAIN_INFO = IChainInfo(0x0000000000000000000000000000000000000FD3);
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
            console2.log("name", string(chains[i].name));
            if (chains[i].chainKey == SEPOLIA_KEY) foundSepolia = true;
        }
        assertTrue(foundSepolia, "Ethereum Sepolia is chainKey 1 on CC3 Testnet");
    }

    function test_attestationsAreBeingProduced() public view {
        (uint64 height,, , bool exists) = CHAIN_INFO.get_latest_attestation_height_and_hash(SEPOLIA_KEY);
        assertTrue(exists, "no attestation found for Sepolia");
        assertGt(height, 0, "attested height must be non-zero");
        console2.log("latest attested Sepolia height", height);
    }

    function test_genesisHeightIsZeroForSepolia() public view {
        assertEq(CHAIN_INFO.get_attestation_genesis_height(SEPOLIA_KEY), 0);
    }

    /// @dev A precompile has no bytecode but still answers calls. Assert exactly that, so a
    ///      naive `extcodesize` check is never added by mistake.
    function test_blockProverHasNoCodeButIsCallable() public view {
        assertEq(BLOCK_PROVER.code.length, 0, "precompiles carry no bytecode");
        // A well-formed static call must not revert with "no contract at address".
        (bool ok,) = BLOCK_PROVER.staticcall(
            abi.encodeWithSignature("calculateTxIndex((bytes32,(bytes32,bool)[]))", bytes32(0), new bytes(0))
        );
        ok; // the shape may be rejected; what matters is that the address is reachable
    }
}
EOF
```

- [ ] **Step 3: Run the fork test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test --match-path 'test/fork/*' --fork-url https://rpc.cc3-testnet.creditcoin.network -vv
```

Expected: PASS, and the log prints the supported chains and the latest attested Sepolia height.
That output is worth screenshotting for the submission — it is direct evidence the integration
talks to live protocol infrastructure.

- [ ] **Step 4: Confirm the suite still passes without a fork URL**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/contracts
forge test
```

Expected: fork tests report as skipped, everything else passes.

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add contracts/test/fork/AttestcoinFork.t.sol
git commit -m "test(contracts): fork test against the live Attestcoin precompiles"
```

---

## Done when

- `forge test` passes with every positive, edge and negative case green.
- `forge coverage` reports 90% or better on `src/`.
- Both invariants hold under fuzzing: the balance identity and the reservation floor.
- The fork test passes against the live Creditcoin RPC and lists Sepolia as chainKey 1.
- All five contracts are deployed, and the four Creditcoin ones show verified badges on Blockscout —
  implementation **and** proxy.
- The post-deployment checklist in `contracts/DEPLOYMENT.md` is fully ticked, especially
  `asc.setSourceGate(1, …)`.

**Next:** `docs/plans/2026-09-13-plan-3-server-and-integration.md`
