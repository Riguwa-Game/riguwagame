import { parseAbi } from 'viem';

export const arenaEscrowAbi = parseAbi([
  'struct RunResult { bytes32 runId; address player; uint32 waveReached; uint64 score; uint64 endedAt; }',
  'struct Run { address player; address token; uint256 stake; uint256 reserved; bytes32 seed; uint64 startedAt; uint64 deadline; uint8 state; }',
  'event RunStarted(bytes32 indexed runId, address indexed player, address indexed token, uint256 stake, bytes32 seed, uint64 deadline)',
  'event RunSettled(bytes32 indexed runId, address indexed player, uint32 waveReached, uint64 score, uint256 payout)',
  'function runOf(bytes32 runId) view returns (Run)',
  'function activeRunOf(address player) view returns (bytes32)',
  'function hashRunResult(RunResult r) view returns (bytes32)',
  'function settleRun(RunResult r, bytes[] sigs)',
]);

export const doodleGateAbi = parseAbi([
  'event ArenaEntryPaid(address indexed player, bytes32 indexed runRef, uint256 amount)',
  'event PrizePoolFunded(address indexed sponsor, uint256 amount)',
  'function payEntry(bytes32 runRef) payable',
  'function fundPrize() payable',
]);

export const doodleGateAscAbi = parseAbi([
  'struct MerkleProofEntry { bytes32 hash; bool isLeft; }',
  'function execute(uint8 action, uint64 chainKey, uint64 blockHeight, bytes encodedTransaction, bytes32 merkleRoot, MerkleProofEntry[] siblings, bytes32 lowerEndpointDigest, bytes32[] continuityRoots) returns (bool)',
  'function processedQueries(bytes32 queryId) view returns (bool)',
  'function sourceGateOf(uint64 chainKey) view returns (address)',
]);
