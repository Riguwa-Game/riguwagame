import 'dotenv/config';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing required env var ${name}`);
  return v;
}

export const config = {
  creditcoinRpc: process.env.CREDITCOIN_RPC_URL ?? 'https://rpc.cc3-testnet.creditcoin.network',
  creditcoinChainId: 102031,
  sepoliaRpc: process.env.SEPOLIA_RPC_URL ?? '',
  proofBuilderUrl: process.env.PROOF_BUILDER_URL ?? 'https://prover.cc3-testnet.creditcoin.network',
  /// Attestcoin's own key for Sepolia. NOT the EVM chain id (11155111).
  sourceChainKey: Number(process.env.SOURCE_CHAIN_KEY ?? 1),
  arenaEscrow: process.env.ARENA_ESCROW ?? '',
  doodleGateAsc: process.env.DOODLE_GATE_ASC ?? '',
  doodleGateSepolia: process.env.DOODLE_GATE_SEPOLIA ?? '',
  wsPort: Number(process.env.WS_PORT ?? 8920),
  /// How long to wait for Creditcoin's attestors to cover a Sepolia block.
  /// Measured on CC3 testnet: attestation trails the Sepolia head by roughly 20-40 minutes,
  /// so the SDK's default timeout is far too short. Err generous; the relayer is idle while
  /// it waits and a timeout means a paid entry is silently dropped.
  attestWaitMs: Number(process.env.ATTEST_WAIT_MS ?? 60 * 60 * 1000),
  attestPollMs: Number(process.env.ATTEST_POLL_MS ?? 15_000),
  monitorKey: () => required('MONITOR_PRIVATE_KEY'),
} as const;
