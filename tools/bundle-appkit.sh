#!/usr/bin/env bash
# Bundles Reown AppKit + the wagmi adapter + @wagmi/core + viem into ONE browser ES module,
# committed to the game's vendor/ directory.
#
# The game has no build step by design. This runs once, by hand, when a version changes; the
# output is a vendored artifact exactly like three.module.js. Running the game requires nothing.
#
# Note: `wagmi` proper requires React >= 18. The game is vanilla, so this uses `@wagmi/core`,
# which is the framework-agnostic package the WagmiAdapter builds on anyway.
set -euo pipefail

APPKIT_VERSION="1.8.23"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/game/doodleshooter/vendor/appkit/appkit.bundle.js"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
printf '{"name":"appkit-bundle","private":true,"type":"module"}\n' > package.json
npm install --silent \
  "@reown/appkit@${APPKIT_VERSION}" \
  "@reown/appkit-adapter-wagmi@${APPKIT_VERSION}" \
  @wagmi/core viem esbuild

cat > entry.js <<'ENTRY'
export { createAppKit } from '@reown/appkit';
export { WagmiAdapter } from '@reown/appkit-adapter-wagmi';
export { defineChain } from '@reown/appkit/networks';
export {
  getAccount, watchAccount, getChainId, switchChain,
  readContract, writeContract, simulateContract, waitForTransactionReceipt, getBalance,
} from '@wagmi/core';
export {
  parseEther, parseUnits, formatEther, formatUnits, decodeEventLog, parseAbi,
} from 'viem';
ENTRY

mkdir -p "$(dirname "$OUT")"
./node_modules/.bin/esbuild entry.js \
  --bundle --format=esm --platform=browser --target=es2022 --minify \
  --outfile="$OUT"

echo "wrote $OUT"
echo "  raw      $(du -h "$OUT" | cut -f1)"
echo "  gzipped  $(gzip -c "$OUT" | wc -c | awk '{printf "%.1f MB", $1/1048576}')"
echo "  exports  $(grep -o 'export{[^}]*}' "$OUT" | tail -1 | head -c 300)"
