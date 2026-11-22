#!/usr/bin/env bash
# Verify RiferaCursorPieces on Sourcify (full match) with one command.
#
# Usage:
#   AGENT_ID=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F \
#     ./verify.sh <PIECES_ADDRESS> [CHAIN_ID]
#
#   CHAIN_ID defaults to 56 (BNB Chain mainnet). Use 97 for BSC testnet.
#   The constructor arg is taken from the same env var used at deploy time,
#   so the deployed address and the verification arg can never drift apart.
#   Requires: forge + cast on PATH. No API key needed (Sourcify is free).
set -euo pipefail

PIECES="${1:?usage: ./verify.sh <PIECES_ADDRESS> [CHAIN_ID]}"
CHAIN_ID="${2:-56}"
AGENT_ID="${AGENT_ID:?AGENT_ID env var required (Binance Agent ID contract)}"

echo "Verifying on Sourcify (chain $CHAIN_ID)..."
echo "  RiferaCursorPieces: $PIECES"

forge verify-contract "$PIECES" contracts/RiferaCursorPieces.sol:RiferaCursorPieces \
  --chain-id "$CHAIN_ID" --verifier sourcify --watch \
  --constructor-args "$(cast abi-encode "constructor(address)" "$AGENT_ID")"

echo "Done. Check full match at https://sourcify.dev/ (search the address)."
