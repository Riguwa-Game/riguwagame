/// Relays one already-paid Sepolia transaction to Creditcoin.
///
/// Useful when the watcher was not running, or when a relay timed out waiting for attestation
/// and the entry would otherwise be silently dropped.
///
///   npm run relay -- <txHash> [action]
///   action 0 = ArenaEntryPaid (default), 1 = PrizePoolFunded
import { createPublicClient, http, type Hex } from 'viem';
import { sepolia } from 'viem/chains';
import { config } from '../src/config.ts';
import { makeRelayer } from '../src/relayer/index.ts';

const txHash = process.argv[2] as Hex | undefined;
const action = Number(process.argv[3] ?? 0);
if (!txHash || !/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
  console.error('usage: npm run relay -- <txHash> [action]');
  process.exit(1);
}

const client = createPublicClient({ chain: sepolia, transport: http(config.sepoliaRpc) });
const receipt = await client.getTransactionReceipt({ hash: txHash });
console.log(`tx ${txHash} is in Sepolia block ${receipt.blockNumber}, status ${receipt.status}`);
if (receipt.status !== 'success') {
  console.error('that transaction reverted on Sepolia; the ASC would refuse it anyway');
  process.exit(1);
}

await makeRelayer()(action, txHash, receipt.blockNumber);
