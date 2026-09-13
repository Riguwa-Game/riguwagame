// Contract calls for the staked solo run, over @wagmi/core.
import {
  readContract, writeContract, waitForTransactionReceipt, decodeEventLog,
  parseEther, parseUnits, formatEther, formatUnits,
} from 'appkit';
import { ADDRESSES, NATIVE, arenaEscrowAbi, usdtAbi, seasonRegistryAbi } from './config.js';
import { wagmiConfig, currentAddress } from './wallet.js';

export const isNative = (token) => token.toLowerCase() === NATIVE.toLowerCase();
export const toUnits = (token, human) => (isNative(token) ? parseEther(human) : parseUnits(human, 6));
export const fromUnits = (token, raw) => (isNative(token) ? formatEther(raw) : formatUnits(raw, 6));

const escrow = (fn, args, extra = {}) =>
  ({ address: ADDRESSES.arenaEscrow, abi: arenaEscrowAbi, functionName: fn, args, ...extra });

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

  const hash = await writeContract(
    wagmiConfig,
    escrow('startRun', [token, value], isNative(token) ? { value } : {}),
  );
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
