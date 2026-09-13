# Deploying to riguwa.xyz

The game is a static folder and can be hosted anywhere. **`ink-monitor` cannot be serverless** and
needs the VPS. This document is written against what is actually running on that box today.

## Why the monitor cannot be serverless

| Requirement | Why serverless fails |
| --- | --- |
| Holds persistent WebSocket connections for the length of a run | Functions are request-scoped; the socket dies with the response |
| Waits 20–40 minutes for Creditcoin to attest a Sepolia block | Execution limits are 10 s to 15 min |
| Holds a hot signing key and submits transactions | Needs a stable process, not a cold start |

## The VPS as found

`ssh ubuntu@43.159.63.76` — Ubuntu 24.04, passwordless sudo, nvm installed for `ubuntu`.

**This box hosts unrelated projects. Do not touch them.**

| Already there | Detail |
| --- | --- |
| nginx on 80/443 | sites: `default`, `hellofugu-api`, `swipenit` |
| certbot 2.9.0 | existing certs for `api.hellofugu.xyz`, `ws.swipenit.fun` |
| Docker stack | `fugugent-prod-{api,postgres,redis,fuguguardian}` on localhost ports |
| Other units | `9router.service`, `claude-bot.service`, a `next-server` on `127.0.0.1:20128` |
| Port 8920 | **free** — this is what ink-monitor takes |

`ws.swipenit.fun` already proves this box terminates TLS for a WebSocket, so the pattern is
established; we just add one more of the same shape.

**Rule for every step below: add a new file, never edit an existing one.**

## 1. DNS

Today `riguwa.xyz` points at Hostinger parking (`A @ → 2.57.91.91`). Point it at the VPS and add the
monitor subdomain.

| Type | Name | Value | TTL |
| --- | --- | --- | --- |
| A | `@` | `43.159.63.76` | 300 |
| A | `monitor` | `43.159.63.76` | 300 |
| CNAME | `www` | `riguwa.xyz` | 300 (already present) |

Wait for propagation before requesting certificates, or certbot's HTTP-01 challenge fails:

```bash
dig +short riguwa.xyz monitor.riguwa.xyz
```

## 2. Reown

Project `4553a4639c46b13a8f3da08c527a28e5` must list **every** origin the game is served from:
`riguwa.xyz`, `www.riguwa.xyz`, and `localhost` for development. Wallets verify `metadata.url`
against this list; a missing entry shows up as a failed or untrusted connection.

## 3. Ship the files

```bash
# from the repo root, on your machine
rsync -avz --delete game/doodleshooter/ ubuntu@43.159.63.76:/var/www/riguwa/
rsync -avz --delete --exclude node_modules --exclude .env \
      server/ ubuntu@43.159.63.76:/opt/ink-monitor/
```

Then on the VPS:

```bash
cd /opt/ink-monitor
cp .env.example .env && chmod 600 .env    # fill it in — MONITOR_PRIVATE_KEY especially
source ~/.nvm/nvm.sh && nvm install 24 && nvm use 24
npm ci --omit=dev
node --experimental-strip-types src/check-attestcoin.ts   # proves the SDK reaches the chain
```

`.env` must never be rsynced — it is excluded above and gitignored. Copy it by hand.

## 4. systemd unit — a new file

`/etc/systemd/system/ink-monitor.service`:

```ini
[Unit]
Description=Inkstake Arena run monitor and Attestcoin relayer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/ink-monitor
EnvironmentFile=/opt/ink-monitor/.env
ExecStart=/home/ubuntu/.nvm/versions/node/v24.10.0/bin/node --experimental-strip-types src/index.ts
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# the key is the only thing of value here; keep the blast radius small
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/opt/ink-monitor

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ink-monitor
journalctl -u ink-monitor -f
```

Check the exact node path first — `readlink -f "$(source ~/.nvm/nvm.sh && nvm which 24)"`.

## 5. nginx — a new site file

`/etc/nginx/sites-available/riguwa`. **Create it; do not touch `default`, `hellofugu-api` or
`swipenit`.**

```nginx
# the game — static
server {
    listen 80;
    listen [::]:80;
    server_name riguwa.xyz www.riguwa.xyz;
    root /var/www/riguwa;
    index index.html;

    # the vendored AppKit bundle is 4.4 MB and never changes without a filename change
    location /vendor/ { expires 30d; add_header Cache-Control "public, immutable"; }
    location / { try_files $uri $uri/ /index.html; }
}

# the monitor — WebSocket
server {
    listen 80;
    listen [::]:80;
    server_name monitor.riguwa.xyz;

    location / {
        proxy_pass http://127.0.0.1:8920;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        # a run can be quiet between waves; do not cut the socket
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/riguwa /etc/nginx/sites-enabled/riguwa
sudo nginx -t && sudo systemctl reload nginx
```

`nginx -t` before reload, every time. A syntax error takes down the other projects too.

## 6. TLS

```bash
sudo certbot --nginx -d riguwa.xyz -d www.riguwa.xyz -d monitor.riguwa.xyz
```

certbot edits **only** the `riguwa` server blocks it is given. Renewal is already installed on this
box for the other domains, so nothing new is needed there.

A page served over `https://riguwa.xyz` **cannot** open a `ws://` socket — browsers block it as
mixed content. `monitor.riguwa.xyz` must have a certificate, or the game will connect to nothing.

## 7. Verify

```bash
curl -sI https://riguwa.xyz | head -1
curl -sI https://riguwa.xyz/vendor/appkit/appkit.bundle.js | head -1
curl -si -o /dev/null -w '%{http_code}\n' \
     -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
     https://monitor.riguwa.xyz/                     # expect 101
systemctl is-active ink-monitor
```

Then in the browser at `https://riguwa.xyz`: the console must be clean — in particular **no Reown
project-id error**, which is the loud one this build prints if the id or the registered domain is
wrong. Connect a wallet, stake, play, die, and confirm the payout settles.

## 8. Hardening

The box was audited before writing this. What was already right, and what was not.

### Already correct — do not undo it

| | |
| --- | --- |
| `PasswordAuthentication no` | Keys only. **1,641 failed SSH attempts in 24 h and not one can succeed.** |
| `PermitRootLogin no` | Root cannot log in over SSH at all. |
| Docker services on `127.0.0.1` | `fugugent-prod-*` are not reachable from the internet. |
| `unattended-upgrades` enabled | Security updates install themselves. |

### What ink-monitor does about its own exposure

The monitor binds **`127.0.0.1:8920`**, not `0.0.0.0`. nginx terminates TLS and proxies in, so there
is no reason to listen publicly — and with no firewall on the box, binding `0.0.0.0` would put a
process holding a signing key straight on the internet.

It also checks the `Origin` header on every handshake. A browser always sends it, so this stops
another site from driving the monitor — and its attestor key — from a victim's browser.

```
http://127.0.0.1:8910    ALLOWED
https://riguwa.xyz       ALLOWED
https://evil.example.com REFUSED (403)
```

Both are set in `.env` (`WS_HOST`, `ALLOWED_ORIGINS`). **If you ever set `WS_HOST=0.0.0.0`, the
monitor is on the public internet with no firewall in front of it.**

### Worth fixing on the box

Ordered by how much they matter. None touches the other projects.

**1. Firewall.** `ufw` is inactive. Nothing is exposed today because only 22/80/443 listen — but
that is luck, not policy. One misconfigured service and it is on the internet.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'ssh'
sudo ufw allow 80/tcp comment 'http'
sudo ufw allow 443/tcp comment 'https'
sudo ufw --force enable
sudo ufw status verbose
```

> Enable it **from a second SSH session you keep open**, so a mistake in the rules does not lock you
> out of your own box. Docker writes its own iptables rules and bypasses ufw for published ports —
> another reason every container here stays bound to `127.0.0.1`.

**2. fail2ban.** 1,641 attempts a day cannot succeed, but they burn CPU and bury real events in the
logs.

```bash
sudo apt install -y fail2ban
sudo tee /etc/fail2ban/jail.local >/dev/null <<'JAIL'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
JAIL
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

**3. 198 pending security updates.** `unattended-upgrades` is enabled yet 198 are outstanding —
usually because they need a reboot, or are held back.

```bash
sudo apt update && sudo apt upgrade -y
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required
```

> **Reboot with care** — other people's services live here. Check what comes back up:
> `systemctl list-units --state=failed`.

### The attestor key

The real asset on this box is `MONITOR_PRIVATE_KEY`.

- It is an **attestor key, never an owner key**. It can sign a `RunResult` and submit proofs. It
  cannot move pool funds, cannot upgrade a contract, cannot change a cap.
- Keep only what it needs for gas. Not a treasury.
- `chmod 600 /opt/ink-monitor/.env`, owned by `ubuntu`.
- The systemd unit runs with `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges`.
- If it leaks: `escrow.setAttestor(old,false)` then `setAttestor(new,true)`. Two transactions and
  the old key is inert.

## 9. Keep it alive

| Thing | Why | Check |
| --- | --- | --- |
| **Monitor gas** | It pays for every relay and every settlement. Empty means settlement falls back to asking the player to sign. | `cast balance <attestor> --rpc-url … --ether` |
| **Reward pool** | Must stay at or above `maxStake x 3`, or staking reverts with `PoolTooSmall`. | `cast call <escrow> "poolOf(address)"` |
| **The unit** | `Restart=always` covers crashes; reboots are covered by `enable`. | `systemctl is-active ink-monitor` |

## Rollback

```bash
sudo systemctl stop ink-monitor && sudo systemctl disable ink-monitor
sudo rm /etc/nginx/sites-enabled/riguwa
sudo nginx -t && sudo systemctl reload nginx
```

Nothing else on the box is touched by any step in this document.
