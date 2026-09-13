import { privateKeyToAccount } from 'viem/accounts';
import type { Account, TypedDataDomain, Hex } from 'viem';

/// uint64 maps to bigint in viem, and the on-chain struct is the authority here.
export type RunResult = {
  runId: Hex;
  player: Hex;
  waveReached: number;
  score: bigint;
  endedAt: bigint;
};

/// Must match ArenaEscrow.RUN_RESULT_TYPEHASH exactly. test/signer.test.ts pins the preimage.
export const RUN_RESULT_TYPES = {
  RunResult: [
    { name: 'runId', type: 'bytes32' },
    { name: 'player', type: 'address' },
    { name: 'waveReached', type: 'uint32' },
    { name: 'score', type: 'uint64' },
    { name: 'endedAt', type: 'uint64' },
  ],
} as const;

/// Must match __EIP712_init("InkstakeArena", "1") in ArenaEscrow.
export function runResultDomain(chainId: number, verifyingContract: Hex): TypedDataDomain {
  return { name: 'InkstakeArena', version: '1', chainId, verifyingContract };
}

export function monitorAccount(privateKey: Hex): Account {
  return privateKeyToAccount(privateKey);
}

export async function signRunResultWith(
  account: Account,
  domain: TypedDataDomain,
  result: RunResult,
): Promise<Hex> {
  if (!account.signTypedData) throw new Error('account cannot sign typed data');
  return account.signTypedData({
    domain,
    types: RUN_RESULT_TYPES,
    primaryType: 'RunResult',
    message: result,
  });
}
