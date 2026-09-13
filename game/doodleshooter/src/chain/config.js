// Chain, wallet and contract configuration.
import { defineChain, parseAbi } from 'appkit';

// Reown AppKit project id.
// NOTE: this is Reown's PUBLIC DOCUMENTATION project id, intended for localhost only. Before
// deploying to a real domain, create a project at https://dashboard.reown.com, put its id here,
// and register the deployed domain there - wallets verify `metadata.url` against it, and a
// mismatch shows up as a failed or untrusted connection.
export const REOWN_PROJECT_ID = 'b56e18d47c72ab683b10814fe9495694';

export const CHAIN = {
  id: 102031,
  name: 'Creditcoin Testnet',
  rpc: 'https://rpc.cc3-testnet.creditcoin.network',
  explorer: 'https://creditcoin-testnet.blockscout.com',
  currency: { name: 'Testnet Creditcoin', symbol: 'tCTC', decimals: 18 },
};

export const creditcoinTestnet = defineChain({
  id: CHAIN.id,
  caipNetworkId: `eip155:${CHAIN.id}`,
  chainNamespace: 'eip155',
  name: CHAIN.name,
  nativeCurrency: CHAIN.currency,
  rpcUrls: { default: { http: [CHAIN.rpc] } },
  blockExplorers: { default: { name: 'Blockscout', url: CHAIN.explorer } },
  testnet: true,
});

// Deployed 2026-09-13. See contracts/DEPLOYMENT.md.
export const ADDRESSES = {
  arenaEscrow: '0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7',
  usdt: '0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1',
  seasonRegistry: '0xc588f37d165dd2B80AD95532aC5a8a975C732050',
};

export const MONITOR_WS = 'ws://127.0.0.1:8920';

// Native tCTC is address(0) in the escrow.
export const NATIVE = '0x0000000000000000000000000000000000000000';

// Token marks shown in the staking UI. See public/README.md for provenance.
export const TOKEN_LOGOS = {
  ctc: './public/ctc.png',
  usdt: './public/usdt.svg',
};

export const arenaEscrowAbi = parseAbi([
  'struct RunResult { bytes32 runId; address player; uint32 waveReached; uint64 score; uint64 endedAt; }',
  'struct Run { address player; address token; uint256 stake; uint256 reserved; bytes32 seed; uint64 startedAt; uint64 deadline; uint8 state; }',
  'struct Pool { uint256 free; uint256 reserved; uint256 activeStake; }',
  'event RunStarted(bytes32 indexed runId, address indexed player, address indexed token, uint256 stake, bytes32 seed, uint64 deadline)',
  'event RunSettled(bytes32 indexed runId, address indexed player, uint32 waveReached, uint64 score, uint256 payout)',
  'function startRun(address token, uint256 amount) payable returns (bytes32)',
  'function settleRun(RunResult r, bytes[] sigs)',
  'function abandonRun(bytes32 runId)',
  'function runOf(bytes32 runId) view returns (Run)',
  'function activeRunOf(address player) view returns (bytes32)',
  'function maxStakeOf(address token) view returns (uint256)',
  'function poolOf(address token) view returns (Pool)',
  'function multiplierBpsFor(uint32 wave) view returns (uint32)',
]);

export const usdtAbi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function faucet()',
]);

export const seasonRegistryAbi = parseAbi([
  'struct PlayerStats { uint32 bestWave; uint64 bestScore; uint32 runs; uint32 wins; uint256 totalStaked; uint256 totalWon; }',
  'function currentSeason() view returns (uint64)',
  'function statsOf(uint64 season, address player) view returns (PlayerStats)',
]);
