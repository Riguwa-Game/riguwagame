#!/usr/bin/env bash
# Verifies every deployed contract on Creditcoin Blockscout: the four implementations and the
# four ERC1967 proxies. Blockscout needs no API key.
#
# The proxies must be verified too, or Blockscout will not render a Read/Write Contract tab.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
set -a && source .env && set +a

DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
PROXY='lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy'
V=(--chain 102031 --verifier blockscout --verifier-url https://creditcoin-testnet.blockscout.com/api --skip-is-verified-check --watch)

ok=0; fail=0
verify() { # <label> <address> <path:Name> [ctor-args-hex]
  local label="$1" addr="$2" target="$3" args="${4:-}"
  printf '\n--- %s (%s)\n' "$label" "$addr"
  if [ -n "$args" ]; then
    forge verify-contract "$addr" "$target" "${V[@]}" --constructor-args "$args" 2>&1 | tail -3
  else
    forge verify-contract "$addr" "$target" "${V[@]}" 2>&1 | tail -3
  fi
  if [ ${PIPESTATUS[0]:-1} -eq 0 ]; then ok=$((ok+1)); else fail=$((fail+1)); fi
}

echo "===== implementations ====="
verify "SeasonRegistry impl" "$IMPL_SEASON_REGISTRY"  src/SeasonRegistry.sol:SeasonRegistry
verify "USDT impl"           "$IMPL_USDT"             src/USDT.sol:USDT
verify "ArenaEscrow impl"    "$IMPL_ARENA_ESCROW"     src/ArenaEscrow.sol:ArenaEscrow
verify "DoodleGateASC impl"  "$IMPL_DOODLE_GATE_ASC"  src/asc/DoodleGateASC.sol:DoodleGateASC

echo
echo "===== proxies ====="
INIT1=$(cast calldata "initialize(address)" "$DEPLOYER")
verify "SeasonRegistry proxy" "$SEASON_REGISTRY" "$PROXY" \
  "$(cast abi-encode 'constructor(address,bytes)' "$IMPL_SEASON_REGISTRY" "$INIT1")"
verify "USDT proxy" "$USDT_TOKEN" "$PROXY" \
  "$(cast abi-encode 'constructor(address,bytes)' "$IMPL_USDT" "$INIT1")"

INIT2=$(cast calldata "initialize(address,address)" "$DEPLOYER" "$SEASON_REGISTRY")
verify "ArenaEscrow proxy" "$ARENA_ESCROW" "$PROXY" \
  "$(cast abi-encode 'constructor(address,bytes)' "$IMPL_ARENA_ESCROW" "$INIT2")"

INIT3=$(cast calldata "initialize(address,address,address)" "$DEPLOYER" "$USDT_TOKEN" "$ARENA_ESCROW")
verify "DoodleGateASC proxy" "$DOODLE_GATE_ASC" "$PROXY" \
  "$(cast abi-encode 'constructor(address,bytes)' "$IMPL_DOODLE_GATE_ASC" "$INIT3")"

echo
echo "===== $ok verified, $fail failed ====="

# NOTE: --skip-is-verified-check is required. All four ERC1967Proxy deployments share identical
# runtime bytecode, so forge's pre-check sees the first one verified and reports the other three
# as "already verified - skipping" when they are not. Blockscout's API is the authority:
#   curl -s https://creditcoin-testnet.blockscout.com/api/v2/addresses/<addr> | jq .is_verified
