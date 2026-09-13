// WebSocket client for ink-monitor. Sends compact run events, receives the signed result.
// Deliberately tiny: wave starts, kills, damage and death. Never 60 Hz state.
import { MONITOR_WS } from '../chain/config.js';

let ws = null, ready = false, queue = [], errorCb = null;
const cbs = { settling: null, settled: null, settleFailed: null };

export const isConnected = () => ready;
export function onSettling(cb) { cbs.settling = cb; }
export function onSettled(cb) { cbs.settled = cb; }
export function onSettleFailed(cb) { cbs.settleFailed = cb; }
export function onError(cb) { errorCb = cb; }

export function openMonitor({ runId, player }) {
  closeMonitor();
  return new Promise((resolve, reject) => {
    try { ws = new WebSocket(MONITOR_WS); } catch (err) { reject(err); return; }
    let settled = false;
    const done = (fn, arg) => { if (!settled) { settled = true; clearTimeout(timer); fn(arg); } };
    const timer = setTimeout(() => done(reject, new Error('the monitor did not respond')), 8000);

    ws.addEventListener('open', () => ws.send(JSON.stringify({ t: 'hello', runId, player })));
    ws.addEventListener('message', (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.t === 'ready') {
        ready = true;
        for (const m of queue) ws.send(JSON.stringify(m));
        queue = [];
        done(resolve, msg);
      } else if (msg.t === 'settling') {
        if (cbs.settling) cbs.settling(msg.signature);
      } else if (msg.t === 'settled') {
        if (cbs.settled) cbs.settled(msg.hash);
      } else if (msg.t === 'settleFailed') {
        if (cbs.settleFailed) cbs.settleFailed(msg.reason, msg.signature, msg.result);
      } else if (msg.t === 'error') {
        ready = false;
        if (errorCb) errorCb(msg.reason);
        done(reject, new Error(msg.reason));
      }
    });
    ws.addEventListener('close', () => { ready = false; });
    ws.addEventListener('error', () => done(reject, new Error('could not reach the monitor')));
  });
}

function send(msg) {
  if (ready && ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  else queue.push(msg);
}

export const reportWave = (n) => send({ t: 'wave', n });
export const reportKill = (wave, enemy) => send({ t: 'kill', wave, enemy });
export const reportDamage = (wave, amount) => send({ t: 'damage', wave, amount });
export const reportDeath = (wave, score) => send({ t: 'died', wave, score });

export function closeMonitor() {
  ready = false; queue = [];
  if (ws) { try { ws.close(); } catch { /* already gone */ } }
  ws = null;
}
