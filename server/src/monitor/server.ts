import { WebSocketServer, type WebSocket } from 'ws';
import { getAddress, type Hex } from 'viem';
import { config } from '../config.ts';
import { publicClient, walletClient } from '../chain.ts';
import { arenaEscrowAbi } from '../abi.ts';
import { runResultDomain, signRunResultWith, monitorAccount, type RunResult } from '../signer.ts';
import { RunSession, SessionError, type ClientEvent } from './session.ts';

const STATE_ACTIVE = 1;
const IDLE_TIMEOUT_MS = 90_000;

export function startMonitor(): WebSocketServer {
  const account = monitorAccount(config.monitorKey() as Hex);
  const domain = runResultDomain(config.creditcoinChainId, config.arenaEscrow as Hex);
  const wallet = walletClient();

  const wss = new WebSocketServer({ port: config.wsPort });
  console.log(`[monitor] listening on :${config.wsPort} as ${account.address}`);

  wss.on('connection', (ws: WebSocket) => {
    let session: RunSession | null = null;
    let idle: NodeJS.Timeout;

    const fail = (reason: string) => {
      console.log(`[monitor] refused: ${reason}`);
      try {
        ws.send(JSON.stringify({ t: 'error', reason }));
      } catch {
        /* already gone */
      }
      ws.close();
    };

    const settle = async (result: RunResult) => {
      const signature = await signRunResultWith(account, domain, result);
      console.log(
        `[monitor] signed run ${result.runId.slice(0, 10)}… wave ${result.waveReached} score ${result.score}`,
      );
      const payload = JSON.stringify({
        t: 'signed',
        result: {
          runId: result.runId,
          player: result.player,
          waveReached: result.waveReached,
          score: result.score.toString(),
          endedAt: result.endedAt.toString(),
        },
        signature,
      });
      if (ws.readyState === ws.OPEN) {
        ws.send(payload);
        return;
      }
      // The client vanished. Submit it ourselves so the stake is not left to time out.
      try {
        const hash = await wallet.writeContract({
          address: config.arenaEscrow as Hex,
          abi: arenaEscrowAbi,
          functionName: 'settleRun',
          args: [result, [signature]],
        });
        console.log(`[monitor] client gone, settled on their behalf: ${hash}`);
      } catch (err) {
        console.error('[monitor] self-settle failed:', err instanceof Error ? err.message : err);
      }
    };

    const touch = () => {
      clearTimeout(idle);
      idle = setTimeout(() => {
        if (session && !session.isFinished()) void settle(session.finishOnDisconnect());
        ws.close();
      }, IDLE_TIMEOUT_MS);
    };
    touch();

    ws.on('message', async (raw) => {
      touch();
      let msg: { t: string } & Record<string, unknown>;
      try {
        msg = JSON.parse(String(raw));
      } catch {
        return fail('malformed message');
      }

      if (msg.t === 'hello') {
        if (session) return fail('already registered');
        let player: Hex;
        try {
          player = getAddress(String(msg.player ?? '')) as Hex;
        } catch {
          return fail('bad player address');
        }
        const runId = String(msg.runId ?? '') as Hex;
        if (!/^0x[0-9a-fA-F]{64}$/.test(runId)) return fail('bad runId');

        // A socket is only accepted for a run that genuinely exists on-chain and is Active.
        let run;
        try {
          run = await publicClient.readContract({
            address: config.arenaEscrow as Hex,
            abi: arenaEscrowAbi,
            functionName: 'runOf',
            args: [runId],
          });
        } catch {
          return fail('could not read the run from the chain');
        }
        if (Number(run.state) !== STATE_ACTIVE) return fail('run is not active on-chain');
        if (getAddress(run.player) !== player) return fail('player does not own this run');

        session = new RunSession({
          runId,
          player,
          seed: run.seed,
          startedAt: Date.now() / 1000,
        });
        console.log(`[monitor] run ${runId.slice(0, 10)}… accepted for ${player}`);
        ws.send(JSON.stringify({ t: 'ready', seed: run.seed }));
        return;
      }

      if (!session) return fail('send hello first');

      session.setClock(Date.now() / 1000);
      try {
        session.handle(msg as unknown as ClientEvent);
      } catch (err) {
        if (err instanceof SessionError) return fail(err.message);
        throw err;
      }

      if (msg.t === 'died') {
        await settle(session.finish());
        clearTimeout(idle);
        ws.close();
      }
    });

    ws.on('close', () => clearTimeout(idle));
    ws.on('error', () => clearTimeout(idle));
  });

  return wss;
}
