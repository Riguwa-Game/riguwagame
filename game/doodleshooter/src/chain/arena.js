// Contract calls for the staked solo run, over @wagmi/core.
import {
  readContract, writeContract, waitForTransactionReceipt, decodeEventLog, getBalance,
  simulateContract, parseEther, parseUnits, formatEther, formatUnits,
} from 'appkit';
import { ADDRESSES, NATIVE, arenaEscrowAbi, usdtAbi, seasonRegistryAbi } from './config.js';
import { wagmiConfig, currentAddress } from './wallet.js';

export const isNative = (token) => token.toLowerCase() === NATIVE.toLowerCase();
export const toUnits = (token, human) => (isNative(token) ? parseEther(human) : parseUnits(human, 6));
export const fromUnits = (token, raw) => (isNative(token) ? formatEther(raw) : formatUnits(raw, 6));

const escrow = (fn, args, extra = {}) =>
  ({ address: ADDRESSES.arenaEscrow, abi: arenaEscrowAbi, functionName: fn, args, ...extra });

/// Wallets report a reverted simulation as "an internal error was received", which tells the
/// player nothing. Walk the viem error chain for the decoded custom error and say what happened.
function explain(err, token) {
  let e = err;
  while (e) {
    const name = e.data?.errorName ?? e.errorName;
    const a = e.data?.args ?? e.args ?? [];
    if (name === 'PoolTooSmall') {
      return `the reward pool cannot back that stake right now — it has ${fromUnits(token, a[0])} free and would need ${fromUnits(token, a[1])}`;
    }
    if (name === 'StakeAboveCap') return `the maximum stake is ${fromUnits(token, a[1])}`;
    if (name === 'RunAlreadyActive') return 'you already have a run in progress — resume or end it first';
    if (name === 'TokenNotAllowed') return 'that token is not accepted for staking';
    if (name === 'ZeroAmount') return 'enter an amount above zero';
    if (name === 'BadValue') return 'the amount sent did not match the stake';
    e = e.cause;
  }
  const m = err?.shortMessage || err?.message || String(err);
  return /user rejected|denied/i.test(m) ? 'you declined the transaction' : m;
}

/// Stake and start a run. Returns the runId and the seed the game must use.
export async function startStakedRun({ token, amount }) {
  const player = currentAddress();
  if (!player) throw new Error('Connect a wallet first');
  const value = toUnits(token, String(amount));

  const cap = await readContract(wagmiConfig, escrow('maxStakeOf', [token]));
  if (value > cap) throw new Error(`The maximum stake is ${fromUnits(token, cap)}`);

  if (!isNative(token)) {
    const allowance = await readContract(wagmiConfig, {
      address: ADDRESSES.usdt, abi: usdtAbi, functionName: 'allowance',
      args: [player, ADDRESSES.arenaEscrow],
    });
    if (allowance < value) {
      const approveHash = await writeContract(wagmiConfig, {
        address: ADDRESSES.usdt, abi: usdtAbi, functionName: 'approve',
        args: [ADDRESSES.arenaEscrow, value],
      });
      await waitForTransactionReceipt(wagmiConfig, { hash: approveHash });
    }
  }

  // Simulate first so a revert surfaces as a readable reason instead of the wallet's opaque
  // "internal error", and so the player is never asked to sign a transaction that must fail.
  const req = escrow('startRun', [token, value], isNative(token) ? { value, account: player } : { account: player });
  try {
    await simulateContract(wagmiConfig, req);
  } catch (err) {
    throw new Error(explain(err, token));
  }

  let hash;
  try {
    hash = await writeContract(wagmiConfig, req);
  } catch (err) {
    throw new Error(explain(err, token));
  }
  const receipt = await waitForTransactionReceipt(wagmiConfig, { hash });

  // Pull runId and seed out of the RunStarted event rather than guessing them.
  for (const log of receipt.logs) {
    try {
      const parsed = decodeEventLog({ abi: arenaEscrowAbi, data: log.data, topics: log.topics });
      if (parsed.eventName === 'RunStarted') {
        return { runId: parsed.args.runId, seed: parsed.args.seed, txHash: hash };
      }
    } catch { /* a log from another contract */ }
  }
  throw new Error('RunStarted event not found in the receipt');
}

/// Submit the monitor-signed result. Anyone may call this; the signatures are what count.
export async function submitSettlement(result, signature) {
  const hash = await writeContract(wagmiConfig, escrow('settleRun', [result, [signature]]));
  await waitForTransactionReceipt(wagmiConfig, { hash });
  return hash;
}

export async function abandonRun(runId) {
  const hash = await writeContract(wagmiConfig, escrow('abandonRun', [runId]));
  await waitForTransactionReceipt(wagmiConfig, { hash });
  return hash;
}

export const activeRun = (player) => readContract(wagmiConfig, escrow('activeRunOf', [player]));
export const readRun = (runId) => readContract(wagmiConfig, escrow('runOf', [runId]));
export const readPool = (token) => readContract(wagmiConfig, escrow('poolOf', [token]));

export const readUsdtBalance = (player) =>
  readContract(wagmiConfig, { address: ADDRESSES.usdt, abi: usdtAbi, functionName: 'balanceOf', args: [player] });

export async function claimFaucet() {
  const hash = await writeContract(wagmiConfig, {
    address: ADDRESSES.usdt, abi: usdtAbi, functionName: 'faucet',
  });
  await waitForTransactionReceipt(wagmiConfig, { hash });
  return hash;
}

/// Wallet balance for either currency, in raw units.
export async function readBalance(token, player) {
  if (isNative(token)) {
    const b = await getBalance(wagmiConfig, { address: player });
    return b.value;
  }
  return readUsdtBalance(player);
}

/// Everything the stake panel needs, in one round of reads.
export async function readStakeContext(player) {
  const [nativeBal, usdtBal, nativePool, usdtPool, nativeCap, usdtCap] = await Promise.all([
    readBalance(NATIVE, player),
    readUsdtBalance(player),
    readPool(NATIVE),
    readPool(ADDRESSES.usdt),
    readContract(wagmiConfig, escrow('maxStakeOf', [NATIVE])),
    readContract(wagmiConfig, escrow('maxStakeOf', [ADDRESSES.usdt])),
  ]);
  return {
    [NATIVE]: { balance: nativeBal, pool: nativePool, cap: nativeCap },
    [ADDRESSES.usdt]: { balance: usdtBal, pool: usdtPool, cap: usdtCap },
  };
}

/// The largest stake that can actually succeed right now: the contract cap, what the pool can
/// back at the 3x ceiling, and what the wallet holds - whichever bites first.
export function effectiveMax({ balance, pool, cap }) {
  const backedByPool = pool.free / 3n;
  return [cap, backedByPool, balance].reduce((a, b) => (b < a ? b : a));
}

export async function readStats(player) {
  const season = await readContract(wagmiConfig, {
    address: ADDRESSES.seasonRegistry, abi: seasonRegistryAbi, functionName: 'currentSeason',
  });
  const stats = await readContract(wagmiConfig, {
    address: ADDRESSES.seasonRegistry, abi: seasonRegistryAbi, functionName: 'statsOf',
    args: [season, player],
  });
  return { season, stats };
}
