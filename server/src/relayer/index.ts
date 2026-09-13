import { createPublicClient, http, type Hex, type Log } from 'viem';
import { sepolia } from 'viem/chains';
// The official Attestcoin SDK is ethers-based: PrecompileChainInfoProvider and ProofBuilder both
// take an ethers provider. ethers is therefore scoped to exactly this file - everything else in
// the project is viem. Using the official SDK is worth more than stack purity here.
import { JsonRpcProvider } from 'ethers';
import { chainInfo, proofProvider } from '@gluwa/usc-sdk';

import { config } from '../config.ts';
import { walletClient } from '../chain.ts';
import { doodleGateAbi, doodleGateAscAbi } from '../abi.ts';

const ACTION_ENTRY_PAID = 0;
const ACTION_PRIZE_FUNDED = 1;

type ProofData = {
  chainKey: number | bigint;
  headerNumber: number | bigint;
  txBytes: string;
  merkleProof: { root: string; siblings: { hash: string; isLeft: boolean }[] };
  continuityProof: { lowerEndpointDigest: string; roots: string[] };
};

/// Watches DoodleGate on Sepolia and relays each event to Creditcoin as a proven query.
/// This is what makes cross-chain entry gasless: the player never needs tCTC.
export function startRelayer(): void {
  if (!config.sepoliaRpc || !config.doodleGateSepolia) {
    console.log('[relayer] source chain not configured, skipping');
    return;
  }

  const sepoliaClient = createPublicClient({
    chain: sepolia,
    transport: http(config.sepoliaRpc),
  });
  const wallet = walletClient();

  // ethers, only for the SDK.
  // The cast works around a TypeScript nominal-privates quirk: JsonRpcProvider extends
  // JsonRpcApiProvider at runtime, but their `#private` brands are not structurally assignable
  // across the SDK's declaration boundary. Runtime behaviour is verified by
  // `npm run check:attestcoin`, which drives this exact provider against the live precompile.
  const creditcoinProvider = new JsonRpcProvider(config.creditcoinRpc);
  const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(
    creditcoinProvider as unknown as ConstructorParameters<
      typeof chainInfo.PrecompileChainInfoProvider
    >[0],
  );
  const proofBuilder = new proofProvider.service.ProofBuilder(
    config.sourceChainKey,
    config.proofBuilderUrl,
  );

  const relay = async (action: number, txHash: Hex, height: bigint) => {
    const label = `${txHash.slice(0, 10)}…@${height}`;
    console.log(`[relayer] ${label} action=${action}: waiting for attestation`);

    try {
      // 1. Wait for Creditcoin's attestors to cover this block.
      await chainInfoProvider.waitUntilHeightAttested(config.sourceChainKey, Number(height));
      console.log(`[relayer] ${label}: attested, fetching proof`);

      // 2. Fetch Merkle and continuity proofs. Promptly: a fresh block needs a ~10-hash
      //    continuity proof, a day-old one needs ~1000 and costs more than 10x as much.
      const proof = await proofBuilder.getProof(txHash);
      if (!proof.success || !proof.data) {
        console.error(`[relayer] ${label}: proof generation failed: ${proof.error}`);
        return;
      }
      const d = proof.data as unknown as ProofData;

      // 3. Submit. The ASC verifies the proof itself - we are a courier, not an oracle.
      const hash = await wallet.writeContract({
        address: config.doodleGateAsc as Hex,
        abi: doodleGateAscAbi,
        functionName: 'execute',
        args: [
          action,
          BigInt(d.chainKey),
          BigInt(d.headerNumber),
          d.txBytes as Hex,
          d.merkleProof.root as Hex,
          d.merkleProof.siblings.map((s) => ({ hash: s.hash as Hex, isLeft: s.isLeft })),
          d.continuityProof.lowerEndpointDigest as Hex,
          d.continuityProof.roots as Hex[],
        ],
      });
      console.log(`[relayer] ${label}: relayed in ${hash}`);
    } catch (err) {
      console.error(`[relayer] ${label} failed:`, err instanceof Error ? err.message : err);
    }
  };

  const onLogs = (action: number) => (logs: Log[]) => {
    for (const log of logs) {
      if (!log.transactionHash || log.blockNumber == null) continue;
      void relay(action, log.transactionHash, log.blockNumber);
    }
  };

  sepoliaClient.watchContractEvent({
    address: config.doodleGateSepolia as Hex,
    abi: doodleGateAbi,
    eventName: 'ArenaEntryPaid',
    onLogs: onLogs(ACTION_ENTRY_PAID),
    onError: (e) => console.error('[relayer] entry watch error:', e.message),
  });

  sepoliaClient.watchContractEvent({
    address: config.doodleGateSepolia as Hex,
    abi: doodleGateAbi,
    eventName: 'PrizePoolFunded',
    onLogs: onLogs(ACTION_PRIZE_FUNDED),
    onError: (e) => console.error('[relayer] prize watch error:', e.message),
  });

  console.log(
    `[relayer] watching ${config.doodleGateSepolia} on Sepolia (Attestcoin chainKey ${config.sourceChainKey})`,
  );
}
