#!/usr/bin/env bash
# Export the compiled ABI + bytecode JSON for the browser deploy page.
#
# Usage: ./export-deploy-artifacts.sh
#
# Runs `forge build`, then copies the compiler output file into deploy/.
# The JSON contains the contract `abi`, the creation `bytecode` (what the
# deploy page sends in the deployment transaction) and the
# `deployedBytecode`. The deploy page embeds this file and deploys from the
# user's wallet (no key ever lives in this repo).
# Re-run after every contract change — the deploy page must always use the
# artifacts from the exact source that will be verified on Sourcify.
set -euo pipefail
cd "$(dirname "$0")"

forge build

mkdir -p deploy
cp out/RiferaCursorPieces.sol/RiferaCursorPieces.json deploy/RiferaCursorPieces.json
cp out/RiferaCursorStake.sol/RiferaCursorStake.json deploy/RiferaCursorStake.json

echo "Exported:"
for f in deploy/RiferaCursorPieces.json deploy/RiferaCursorStake.json; do
abi_len=$(python3 -c "import json; d=json.load(open('$f')); print(len(d['abi']))")
bc_len=$(python3 -c "import json; d=json.load(open('$f')); print(len(d['bytecode']['object'])//2)")
echo "  $f  (abi entries: $abi_len, creation bytecode: ${bc_len} bytes)"
done
echo "Deploy page: embed these JSONs (abi + bytecode.object)."
