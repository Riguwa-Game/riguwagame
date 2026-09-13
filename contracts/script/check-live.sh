#!/usr/bin/env bash
# Verifies the Attestcoin protocol is live and answering on Creditcoin Testnet.
#
# This exists because `forge test --fork-url` cannot fork Creditcoin: its blocks carry no
# `mixHash` and `difficulty: 0x0`, so Foundry's backend rejects them with
# "header validation error: `prevrandao` not set". These plain JSON-RPC calls make the same
# assertions and work today.
set -euo pipefail

RPC="${CREDITCOIN_RPC_URL:-https://rpc.cc3-testnet.creditcoin.network}"
CHAIN_INFO=0x0000000000000000000000000000000000000fd3
BLOCK_PROVER=0x0000000000000000000000000000000000000FD2
SEPOLIA_KEY=1

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "== Creditcoin Testnet =="
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
echo "chain id                     : $CHAIN_ID"
[ "$CHAIN_ID" = "102031" ] || fail "expected chain id 102031"

echo
echo "== ChainInfo precompile ($CHAIN_INFO) =="
echo "supported chains             :"
cast call "$CHAIN_INFO" "get_supported_chains()((uint64,uint64,bytes,uint8)[])" --rpc-url "$RPC" | sed 's/^/  /'

ATTESTED=$(cast call "$CHAIN_INFO" "is_height_attested(uint64,uint64)(bool)" $SEPOLIA_KEY 1 --rpc-url "$RPC")
echo "is_height_attested(1, 1)     : $ATTESTED"
[ "$ATTESTED" = "true" ] || fail "Sepolia height 1 is not attested"

echo "latest attestation for Sepolia:"
cast call "$CHAIN_INFO" "get_latest_attestation_height_and_hash(uint64)((uint64,bytes32,bool,bool))" \
  $SEPOLIA_KEY --rpc-url "$RPC" | sed 's/^/  /'

echo
echo "== BlockProver precompile ($BLOCK_PROVER) =="
CODE=$(cast code "$BLOCK_PROVER" --rpc-url "$RPC")
echo "bytecode                     : ${CODE:-0x} (precompiles carry none - this is expected)"

echo
echo "== EVM opcode support (state-override probe) =="
probe() {
  curl -s --max-time 30 -X POST "$RPC" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[
          {\"to\":\"0x00000000000000000000000000000000DeaDBeef\",\"data\":\"0x\"},\"latest\",
          {\"0x00000000000000000000000000000000DeaDBeef\":{\"code\":\"$1\"}}]}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result'); print('ok' if r and int(r,16)!=0 else 'REJECTED')"
}
echo "PUSH0   (shanghai)           : $(probe 0x5f600152600160005260206000f3)"
echo "MCOPY   (cancun)             : $(probe 0x6020600060005e600160005260206000f3)"
echo "TSTORE  (cancun)             : $(probe 0x604260005d60005c60005260206000f3)"
echo "BLOBBASEFEE (cancun)         : $(probe 0x4a60005260206000f3)   <- expected REJECTED"

echo
echo "All live checks passed."
