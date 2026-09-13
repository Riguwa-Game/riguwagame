# Deploying to riguwa.xyz

Two halves, two hosts:

| Half | Host | Why |
| --- | --- | --- |
| The game — a static folder, no build step | **Vercel** (`inkstake-arena`) | A CDN is the right shape for 6 MB of immutable assets, and it is free. |
| `ink-monitor` — WebSocket, signing key, hour-long waits | **The VPS** (`43.159.63.76`) | **It cannot be serverless.** See below. |

This document is written against what is actually running today, not against a plan.

## Why the monitor cannot be serverless

| Requirement | Why serverless fails |
| --- | --- |
| Holds persistent WebSocket connections for the length of a run | Functions are request-scoped; the socket dies with the response |
| Waits 20–40 minutes for Creditcoin to attest a Sepolia block | Execution limits are 10 s to 15 min |
| Holds a hot signing key and submits transactions | Needs a stable process, not a cold start |

## The VPS as found

`ssh ubuntu@43.159.63.76` — Ubuntu 24.04, passwordless sudo.

**This box hosts unrelated projects. Do not touch them.**

| Already there | Detail |
| --- | --- |
| nginx on 80/443 | sites: `default`, `hellofugu-api`, `swipenit` |
| certbot 2.9.0 | existing certs for `api.hellofugu.xyz`, `ws.swipenit.fun` |
| Docker stack | `fugugent-prod-{api,postgres,redis,fuguguardian}` on localhost ports |
| Other units | `9router.service`, `claude-bot.service`, a `next-server` on `127.0.0.1:20128` |
| RAM | **~2 GB total, ~0.5 GB free.** This constrains how we build. |
| Port 8920 | **free** — this is what ink-monitor takes |

`ws.swipenit.fun` already proves this box terminates TLS for a WebSocket, so the pattern is
established; we just add one more of the same shape.

> `ws.swipenit.fun`, `rest.swipenit.fun` and `rpc.swipenit.fun` return **502**. That is not our
> doing and was verified before and after every change here: they proxy to `127.0.0.1:8545`,
> `:1317` and `:26657`, and none of those is listening. A dead Cosmos node, unrelated to this
> project.

**Rule for every step below: add a new file, never edit an existing one.**

## 1. DNS

Records at Hostinger, which keeps the `dns-parking.com` nameservers.

| Action | Type | Name | Value | TTL |
| --- | --- | --- | --- | --- |
| **edit** | A | `@` | `76.76.21.21` | 300 |
| **keep** | A | `monitor` | `43.159.63.76` | 300 |
| **delete** if present | CNAME | `www` | — | — |

`76.76.21.21` is Vercel's apex address. No `www`, and no `api` subdomain — the monitor is the only
VPS-hosted service and it lives at `monitor.riguwa.xyz`.

> **Do not switch the nameservers to Vercel**, even though `vercel domains inspect` offers it. The
> `monitor` record lives at Hostinger; moving the zone to Vercel takes it with it and the game
> loses its monitor. Vercel itself lists the A record as the recommended option for exactly this
> case.

```bash
dig +short riguwa.xyz monitor.riguwa.xyz
```

## 2. Reown

Project `4553a4639c46b13a8f3da08c527a28e5` must list **every** origin the game is served from:
`riguwa.xyz` and `localhost` for development. Wallets verify `metadata.url` against this list; a
missing entry shows up as a failed or untrusted connection.

`https://inkstake-arena.vercel.app` is deliberately **not** registered, and the monitor's
`ALLOWED_ORIGINS` rejects it too. The Vercel hostname is a deployment address, not an entry point:
one canonical origin, one registered domain.

## 3. The game — Vercel

```bash
cd game/doodleshooter
vercel deploy --prod
```

`vercel.json` sets `"outputDirectory": "."`. **This line is load-bearing.** Vercel's zero-config
static build treats a top-level `public/` directory as the output directory, and this project has
one (the two token logos). Without the override the deployment serves `ctc.png` and `usdt.png` at
the site root and 404s on `index.html` — which is exactly what happened the first time.

There is no build step, no `package.json`, no framework preset. Vercel uploads the folder and
serves it.

## 4. The monitor — build here, ship the output

The VPS has ~0.5 GB of RAM free and runs other people's processes. Running `tsc` there risks an
OOM that takes one of them down, so **build on your machine and ship `dist/`**:

```bash
cd server
npm run build                       # -> dist/src/index.js
rsync -az --delete dist/ ubuntu@43.159.63.76:/opt/ink-monitor/dist/
rsync -az package.json package-lock.json ubuntu@43.159.63.76:/opt/ink-monitor/
scp .env ubuntu@43.159.63.76:/opt/ink-monitor/.env
```

On the VPS, Node lives at `/opt/node` — a plain tarball, deliberately **not** on the system `PATH`
and **not** an apt package, so installing it changed nothing for the other projects:

```bash
ssh ubuntu@43.159.63.76
sudo chown inkmonitor:inkmonitor /opt/ink-monitor/.env && sudo chmod 600 /opt/ink-monitor/.env
cd /opt/ink-monitor && PATH=/opt/node/bin:$PATH npm ci --omit=dev
sudo chown -R inkmonitor:inkmonitor /opt/ink-monitor
```

`.env` is gitignored and must never be rsynced from the repo tree as part of a directory sync —
copy it explicitly, as above.

## 5. systemd unit — a new file

`server/deploy/ink-monitor.service`, installed at `/etc/systemd/system/ink-monitor.service`.

It runs as a dedicated system user `inkmonitor` (no shell, no home), under
`ProtectSystem=strict`, `ProtectHome`, `NoNewPrivileges`, a `@system-service` syscall filter, and
`RestrictAddressFamilies=AF_INET AF_INET6`.

It also sets **`MemoryMax=400M`**. That is not about this service's needs — it is so a leak here
can never be the reason one of the other projects on this 2 GB box gets OOM-killed.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ink-monitor
journalctl -u ink-monitor -f
```

## 6. nginx — a new site file

`server/deploy/nginx/monitor.riguwa.xyz.conf`, installed at
`/etc/nginx/sites-available/inkstake-monitor`. **Create it; do not touch `default`,
`hellofugu-api` or `swipenit`.**

It declares nothing at `http` level — no `map $http_upgrade`, no shared upstream — so enabling or
removing it cannot change how any other site behaves. `Connection "upgrade"` is set literally for
that reason.

```bash
sudo ln -sfn /etc/nginx/sites-available/inkstake-monitor /etc/nginx/sites-enabled/inkstake-monitor
sudo nginx -t && sudo systemctl reload nginx
```

`nginx -t` before reload, every time — it validates *all* sites, so a clean result is also proof
you did not break the other projects. A syntax error takes them down with you.

## 7. TLS

```bash
sudo certbot --nginx -d monitor.riguwa.xyz --cert-name monitor.riguwa.xyz
```

certbot appends the `443` block and the port-80 redirect to **only** the site file it is given, and
reuses the ACME account already registered on this box. Renewal is already scheduled here.

The game does not need a certificate from us — Vercel terminates TLS for `riguwa.xyz`.

A page served over `https://riguwa.xyz` **cannot** open a `ws://` socket — browsers block it as
mixed content. `monitor.riguwa.xyz` must have a certificate, or the game connects to nothing.

## 8. Verify

What was actually checked, and the answers that came back:

```
https://riguwa.xyz/                        200  text/html
https://riguwa.xyz/src/main.js             200  application/javascript
https://riguwa.xyz/vendor/appkit/…js       200  4.4 MB
https://riguwa.xyz/public/ctc.png          200  image/png

wss://monitor.riguwa.xyz
  Origin: https://riguwa.xyz               CONNECTED
  Origin: https://evil.example.com         403
  Origin: https://inkstake-arena.vercel.app 403

systemctl is-active ink-monitor            active   (~75 MB)
ss -tlnp | grep 8920                       127.0.0.1:8920 only
nginx -t                                   ok (all sites)
https://api.hellofugu.xyz/                 unchanged
```

Then in the browser at `https://riguwa.xyz`: the console must be clean — in particular **no Reown
project-id error**, which is the loud one this build prints if the id or the registered domain is
wrong. Connect a wallet, stake, play, die, and confirm the payout settles.

## 9. Hardening

### Done

| | |
| --- | --- |
| `PasswordAuthentication no` | Keys only. **1,641 failed SSH attempts in 24 h and not one can succeed.** |
| `PermitRootLogin no` | Root cannot log in over SSH at all. |
| Docker services on `127.0.0.1` | `fugugent-prod-*` are not reachable from the internet. |
| `unattended-upgrades` enabled | Security updates install themselves. |
| **`ufw` active** | `deny incoming`; 22/80/443 only. Enabled from a second SSH session kept open, then SSH survival confirmed before that session was closed. |
| **`fail2ban` active** | `sshd` jail, `maxretry 5`, `bantime 1h`. |
| **`ink-monitor` on `127.0.0.1:8920`** | nginx terminates TLS and proxies in. Never public. |
| **Origin allowlist on the WebSocket** | A browser always sends `Origin`, so this stops another site driving the monitor — and its attestor key — from a victim's browser. |

`WS_HOST` and `ALLOWED_ORIGINS` are set in `.env`. **If you ever set `WS_HOST=0.0.0.0`, the monitor
is on the public internet**; ufw would still deny 8920, but do not make a firewall rule the only
thing standing between a signing key and the world.

> Docker writes its own iptables rules and bypasses ufw for published ports — another reason every
> container here stays bound to `127.0.0.1`.

### Still open — your call

**198 pending security updates.** `unattended-upgrades` is on, yet 198 are outstanding: they are
held back because applying them restarts `nginx`, `openssh` and `systemd`, and the kernel ones need
a reboot. **Every one of those touches the other projects on this box**, which is why this was left
for you rather than done unattended.

```bash
sudo apt update && sudo apt upgrade -y
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required
systemctl list-units --state=failed      # check what did not come back
```

### The attestor key

The real asset on this box is `MONITOR_PRIVATE_KEY`.

- It is an **attestor key, never an owner key**. It can sign a `RunResult` and submit proofs. It
  cannot move pool funds, cannot upgrade a contract, cannot change a cap.
- Keep only what it needs for gas. Not a treasury.
- `chmod 600 /opt/ink-monitor/.env`, owned by `inkmonitor`, read by a service that cannot read
  anything else on the box.
- If it leaks: `escrow.setAttestor(old,false)` then `setAttestor(new,true)`. Two transactions and
  the old key is inert.

## 10. Keep it alive

| Thing | Why | Check |
| --- | --- | --- |
| **Monitor gas** | It pays for every relay and every settlement. Empty means settlement falls back to asking the player to sign. | `cast balance <attestor> --rpc-url … --ether` |
| **Reward pool** | Must stay at or above `maxStake x 3`, or staking reverts with `PoolTooSmall`. | `cast call <escrow> "poolOf(address)"` |
| **The unit** | `Restart=always` covers crashes; reboots are covered by `enable`. | `systemctl is-active ink-monitor` |
| **A stuck relay** | An entry paid on Sepolia whose attestation timed out. | `npm run relay:prod -- <txHash>` |

## Rollback

The monitor, without touching anything else on the box:

```bash
sudo systemctl disable --now ink-monitor
sudo rm /etc/nginx/sites-enabled/inkstake-monitor
sudo nginx -t && sudo systemctl reload nginx
```

The game: Vercel keeps every deployment. Promote an earlier one from the dashboard, or
`vercel rollback`.
