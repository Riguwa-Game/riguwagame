#!/usr/bin/env bash
# Deploys the four UUPS proxies to Creditcoin Testnet and wires them together.
#
# Why not `forge script`? Foundry cannot fork Creditcoin ("header validation error: `prevrandao`
# not set" - Creditcoin blocks carry no mixHash), and `--broadcast` simulates through that same
# fork backend. `forge create` and `cast send` talk to the RPC directly and work fine.
#
# script/Deploy.s.sol remains the canonical, assertion-checked description of this deployment and
# is rehearsed against anvil; this script performs the same steps transaction by transaction.
#
# Run DeploySepolia.s.sol first and set DOODLE_GATE_SEPOLIA, or the ASC ends up with no registered
# emitter and refuses every cross-chain query.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
set -a && source .env && set +a

RPC="${CREDITCOIN_RPC_URL:-https://rpc.cc3-testnet.creditcoin.network}"
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
PROXY='lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy'
VERIFY=(--verifier blockscout --verifier-url https://creditcoin-testnet.blockscout.com/api --chain 102031)

: "${MONITOR_ADDRESS:?set MONITOR_ADDRESS in .env}"
[ -n "${DOODLE_GATE_SEPOLIA:-}" ] || echo "WARNING: DOODLE_GATE_SEPOLIA is empty - the ASC will have no emitter bound"

echo "deployer : $DEPLOYER"
echo "balance  : $(cast balance "$DEPLOYER" --rpc-url "$RPC" --ether) tCTC"
echo

# create <label> <path:Name> [constructor-args...] -> echoes the address
create() {
  local label="$1" target="$2"; shift 2
  local out
  out=$(forge create "$target" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" --broadcast \
        ${1+--constructor-args "$@"} 2>&1) || { echo "$out" >&2; exit 1; }
  local addr
  addr=$(echo "$out" | grep -oE 'Deployed to: 0x[0-9a-fA-F]{40}' | awk '{print $NF}')
  [ -n "$addr" ] || { echo "could not parse address for $label" >&2; echo "$out" >&2; exit 1; }
  echo "  $label -> $addr" >&2
  echo "$addr"
}

send() { cast send "$@" --rpc-url "$RPC" --private-key "$PRIVATE_KEY" >/dev/null; }

echo "== implementations =="
IMPL_REGISTRY=$(create "SeasonRegistry impl" src/SeasonRegistry.sol:SeasonRegistry)
IMPL_USDT=$(create     "USDT impl"           src/USDT.sol:USDT)
IMPL_ESCROW=$(create   "ArenaEscrow impl"    src/ArenaEscrow.sol:ArenaEscrow)
IMPL_ASC=$(create      "DoodleGateASC impl"  src/asc/DoodleGateASC.sol:DoodleGateASC)

echo
echo "== proxies =="
INIT=$(cast calldata "initialize(address)" "$DEPLOYER")
REGISTRY=$(create "SeasonRegistry proxy" "$PROXY" "$IMPL_REGISTRY" "$INIT")
USDT=$(create     "USDT proxy"           "$PROXY" "$IMPL_USDT"     "$INIT")

INIT=$(cast calldata "initialize(address,address)" "$DEPLOYER" "$REGISTRY")
ESCROW=$(create "ArenaEscrow proxy" "$PROXY" "$IMPL_ESCROW" "$INIT")

INIT=$(cast calldata "initialize(address,address,address)" "$DEPLOYER" "$USDT" "$ESCROW")
ASC=$(create "DoodleGateASC proxy" "$PROXY" "$IMPL_ASC" "$INIT")

echo
echo "== wiring =="
send "$REGISTRY" "setEscrow(address)" "$ESCROW";                          echo "  registry.setEscrow"
send "$ESCROW"   "setAsc(address)" "$ASC";                                echo "  escrow.setAsc"
send "$USDT"     "setMinter(address,bool)" "$ASC" true;                   echo "  usdt.setMinter(asc)"
send "$ESCROW"   "setMaxStake(address,uint256)" \
                 0x0000000000000000000000000000000000000000 100000000000000000000; echo "  escrow.setMaxStake(tCTC, 100)"
send "$ESCROW"   "setMaxStake(address,uint256)" "$USDT" 100000000;        echo "  escrow.setMaxStake(USDT, 100)"
send "$ESCROW"   "setAttestor(address,bool)" "$MONITOR_ADDRESS" true;     echo "  escrow.setAttestor(monitor)"
send "$ESCROW"   "setThreshold(uint256)" 1;                               echo "  escrow.setThreshold(1)"
send "$ASC"      "setUsdtPerSourceUnit(uint256)" "${USDT_PER_SOURCE_UNIT:-100000000}"; echo "  asc.setUsdtPerSourceUnit"
send "$ASC"      "setMaxCreditPerQuery(uint256)" "${MAX_CREDIT_PER_QUERY:-1000000000}"; echo "  asc.setMaxCreditPerQuery"
if [ -n "${DOODLE_GATE_SEPOLIA:-}" ]; then
  send "$ASC" "setSourceGate(uint64,address)" 1 "$DOODLE_GATE_SEPOLIA"
  echo "  asc.setSourceGate(chainKey 1 -> $DOODLE_GATE_SEPOLIA)"
fi

echo
echo "== seeding the reward pool =="
send "$USDT"   "mint(address,uint256)" "$DEPLOYER" 1000000000000;                echo "  usdt.mint 1,000,000"
send "$USDT"   "approve(address,uint256)" "$ESCROW" \
               115792089237316195423570985008687907853269984665640564039457584007913129639935; echo "  usdt.approve"
send "$ESCROW" "fundPool(address,uint256)" "$USDT" 100000000000;                 echo "  fundPool 100,000 USDT"
send "$ESCROW" "fundPool(address,uint256)" \
               0x0000000000000000000000000000000000000000 300000000000000000000 --value 300ether; echo "  fundPool 300 tCTC"

echo
echo "== addresses =="
cat <<ADDR
SEASON_REGISTRY=$REGISTRY
USDT_TOKEN=$USDT
ARENA_ESCROW=$ESCROW
DOODLE_GATE_ASC=$ASC

IMPL_SEASON_REGISTRY=$IMPL_REGISTRY
IMPL_USDT=$IMPL_USDT
IMPL_ARENA_ESCROW=$IMPL_ESCROW
IMPL_DOODLE_GATE_ASC=$IMPL_ASC
ADDR
