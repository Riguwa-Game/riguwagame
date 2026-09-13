import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { verifyTypedData, type Hex } from 'viem';
import { runResultDomain, RUN_RESULT_TYPES, signRunResultWith, monitorAccount } from '../src/signer.ts';

const ESCROW = '0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7' as Hex;
const CHAIN_ID = 102031;

const RESULT = {
  runId: ('0x' + '11'.repeat(32)) as Hex,
  player: '0x1111111111111111111111111111111111111111' as Hex,
  waveReached: 12,
  score: 7777n,
  endedAt: 1789000000n,
};

const freshAccount = () => privateKeyToAccount(generatePrivateKey());

test('the typed-data fields match the Solidity typehash preimage', () => {
  // ArenaEscrow computes keccak256 of exactly this string. One character of drift and every
  // settlement reverts with NotAttestor.
  const rendered =
    'RunResult(' +
    RUN_RESULT_TYPES.RunResult.map((f) => `${f.type} ${f.name}`).join(',') +
    ')';
  assert.equal(
    rendered,
    'RunResult(bytes32 runId,address player,uint32 waveReached,uint64 score,uint64 endedAt)',
  );
});

test('the domain matches the contract', () => {
  const d = runResultDomain(CHAIN_ID, ESCROW);
  assert.equal(d.name, 'InkstakeArena');
  assert.equal(d.version, '1');
  assert.equal(d.chainId, CHAIN_ID);
  assert.equal(d.verifyingContract, ESCROW);
});

test('a signature verifies against the signing address', async () => {
  const account = freshAccount();
  const domain = runResultDomain(CHAIN_ID, ESCROW);
  const signature = await signRunResultWith(account, domain, RESULT);
  assert.ok(
    await verifyTypedData({
      address: account.address,
      domain,
      types: RUN_RESULT_TYPES,
      primaryType: 'RunResult',
      message: RESULT,
      signature,
    }),
  );
});

test('a signature is 65 bytes', async () => {
  const sig = await signRunResultWith(freshAccount(), runResultDomain(CHAIN_ID, ESCROW), RESULT);
  assert.equal((sig.length - 2) / 2, 65);
});

test('changing any field changes the signature', async () => {
  const account = freshAccount();
  const domain = runResultDomain(CHAIN_ID, ESCROW);
  const base = await signRunResultWith(account, domain, RESULT);
  for (const patch of [
    { runId: ('0x' + '22'.repeat(32)) as Hex },
    { player: '0x2222222222222222222222222222222222222222' as Hex },
    { waveReached: 13 },
    { score: 7778n },
    { endedAt: 1789000001n },
  ]) {
    const sig = await signRunResultWith(account, domain, { ...RESULT, ...patch });
    assert.notEqual(sig, base, `field ${Object.keys(patch)[0]} must affect the signature`);
  }
});

test('a different chain id produces a different signature', async () => {
  const account = freshAccount();
  const a = await signRunResultWith(account, runResultDomain(CHAIN_ID, ESCROW), RESULT);
  const b = await signRunResultWith(account, runResultDomain(1, ESCROW), RESULT);
  assert.notEqual(a, b, 'domain separation must bind the chain id');
});

test('a different verifying contract produces a different signature', async () => {
  const account = freshAccount();
  const a = await signRunResultWith(account, runResultDomain(CHAIN_ID, ESCROW), RESULT);
  const b = await signRunResultWith(
    account,
    runResultDomain(CHAIN_ID, '0x0000000000000000000000000000000000000001'),
    RESULT,
  );
  assert.notEqual(a, b, 'domain separation must bind the verifying contract');
});

test('monitorAccount derives the address the contract was configured with', () => {
  const key = generatePrivateKey();
  assert.equal(monitorAccount(key).address, privateKeyToAccount(key).address);
});
