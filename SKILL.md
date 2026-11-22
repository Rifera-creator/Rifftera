# Rifera Cursor Pieces (RPIECE) — Agent Skill

## What this is

Rifera Cursor Pieces is a 5-piece pixel-cursor NFT on BNB Chain (chain ID 56).
One ERC721 contract. Five pieces make one cursor: Pointer, Ember, Verdant,
Frost, Void. A cursor broke into five pieces — only AI agents can mint them.
Trade the pieces, forge the cursor, stake it and share the pool.

## Status — read first

- **Contract: NOT DEPLOYED yet.** There is no contract address. Do not
  invent one, do not guess one, do not use an address from another project.
  After deployment, the live address appears in the mint section of the web
  (`index.html`), in `pieces.json` (`contract_address`), and on the deploy
  page (`rifera-pieces-deploy.html`).
- Mint opens CLOSED. The owner opens it with `setMintOpen(true)`.
- Web + game are live. Minting starts only after deployment + mint open.

## When to use this skill

Use it when an agent (or its user) wants to mint Rifera Cursor Pieces,
check a mint price, check remaining supply per piece, or check whether a
wallet holds a complete set. The agent must hold a Binance Agent ID.

## Requirements

- Binance Agent ID: the contract checks `balanceOf(wallet) >= 1` on the
  Agent ID registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`.
  No Agent ID = mint reverts. There is no human mint button.
- BNB on BNB Chain for gas + mint price.

## Mint rules

- Order is sequential per wallet: Pointer -> Ember -> Verdant -> Frost ->
  Void. You cannot skip a piece and cannot mint the same piece twice.
- Prices: Pointer FREE (gas only), Ember / Verdant / Frost / Void
  0.002 BNB each. Full set 0.008 BNB.
- Max 5 pieces per wallet (one set). No batch mint: `mint()` mints one
  piece per call.
- Supply cap: 1,111 per piece type, 5,555 total, 1,111 full sets max.
  If a piece type is sold out, `mint()` and `nextMintQuote()` revert with
  `PieceSoldOut(uint8 piece)`. If Pointer is sold out, no new wallet can
  start minting at all.
- 100% of paid mint BNB goes to the owner in the same transaction.

## How to mint

1. Check Agent ID: `balanceOf(wallet)` on the registry above must be >= 1.
2. Call `nextMintQuote(wallet)` on the RPIECE contract for the exact price
   of the wallet's next piece (0 for Pointer, 0.002 BNB after that).
3. Call `mint()` payable with exactly that amount. Underpay and overpay
   both revert.
4. Repeat steps 2–3 for the next piece until the set of 5 is complete.

## Useful views

- `pieceOf(tokenId)` — which piece a token is (0 Pointer … 4 Void).
- `piecesOf(wallet)` — pieces the wallet holds.
- `tokenIdsOf(wallet)` — token IDs the wallet holds.
- `hasCompleteSet(wallet)` — true when the wallet holds all 5 pieces.
- `totalMinted()` — total pieces minted.
- `mintedPerPiece(uint8)` / `remainingPerPiece(uint8)` — minted and
  remaining per piece type (cap 1,111 each).
- `MAX_SUPPLY_PER_PIECE()` = 1111, `MAX_TOTAL_SUPPLY()` = 5555.
- `mintOpen()` — whether minting is open.
- `tokenURI(tokenId)` — on-chain SVG, a distinct shape per piece.

## Function selectors (verified with cast sig)

- `mint()` 0x1249c58b
- `nextMintQuote(address)` 0x50e3aeae
- `totalMinted()` 0xa2309ff8
- `mintedPerPiece(uint8)` 0xb5368be0
- `remainingPerPiece(uint8)` 0x5efaf243
- `pieceOf(uint256)` 0xa8d514bc
- `piecesOf(address)` 0x82e9f731
- `tokenIdsOf(address)` 0xa3b261f2
- `hasCompleteSet(address)` 0x88e08288
- `nextTokenId()` 0x75794a3c
- `mintOpen()` 0x24bbd049
- `agentId()` 0xe84f43b7
- `MAX_SUPPLY_PER_PIECE()` 0x31e28d12
- `MAX_TOTAL_SUPPLY()` 0x33039d3d
- Error `PieceSoldOut(uint8)` 0x1870b764

## Mint prompt (4 lines, direct execute, no domain)

Mint RPIECE: cek Agent ID di registry 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F, lalu nextMintQuote(wallet) untuk harga pastinya.
Kirim mint() dengan BNB tepat sesuai quote (Pointer FREE, sisanya 0,002 BNB).
1 set = 5 keping maks per wallet, urutan Pointer → Ember → Verdant → Frost → Void.
Cap 1.111 per keping, total 5.555 — kontrak belum deploy, cek alamat live di web dulu.

## Game

Shard Rush (on the web): 100 rounds, 4 rotating styles — RUSH (collect 5
pieces), DODGE (survive the timer), CHASE (catch fleeing pieces), BLITZ
(30 seconds, collect as many as possible). 3 lives, mouse / touch / WASD.
Finish round 100 to become CURSOR MASTER. The game is play only — playing
does not mint anything.

## Staking

RiferaCursorStake — stake a complete set of 5 pieces, earn BNB from the pool.
- Contract: NOT DEPLOYED yet (same as RPIECE — no address yet, do not
  invent one).
- Stake: `stake(uint256[5] tokenIds)` — exactly one of each piece (Pointer 0,
  Ember 1, Verdant 2, Frost 3, Void 4), all owned by the caller, approved
  first. The 5 NFTs lock in the staking contract; `unstake()` returns them
  and pays pending rewards.
- Rewards: 10% of the remaining pool per day (`DAILY_RELEASE_BPS` = 1000),
  split equally among staked sets. Rewards only accrue while at least one
  set is staked; idle days are never paid retroactively.
- Pool: funded manually by the owner from mint revenue via `fundPool()`
  (payable). No automatic split from mint fees. The pool has NO owner
  withdraw — it only leaves via `claim()` / `unstake()` by stakers.
- Claim: `claim()` pays pending BNB any time; `unstake()` auto-pays pending.
- Selectors: `stake(uint256[5])` 0x17c54c64 · `unstake()` 0x2def6620 ·
  `claim()` 0x4e71d92d · `fundPool()` 0x70f37d27 ·
  `pendingReward(address)` 0xf40f0f52 · `poolBalance()` 0x96365d44 ·
  `stakedSets()` 0xc1ca80cc · `stakedBy(address)` 0x5f56a31a

## Files

- `SKILL.md` (this file) — full skill
- `llms.txt` — summary for LLMs
- `agents.txt` — short pointers + mint prompt
- `pieces.json` — machine-readable mint data
- `robots.txt` — agents welcome, points to these files
- `rifera-pieces-deploy.html` — deploy page (owner only)
- `index.html` — web + game
