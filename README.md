# Rifera Cursor Pieces (RPIECE)

Foundry project for the Rifera Cursor Pieces NFT — the 5 sequential pieces
that build one First Cursor in the Rifera Game. Target chain: **BNB Chain
(mainnet, chain 56)**. **Nothing here is deployed yet** — the user deploys
from their own wallet with their own BNB.

## Locked decisions (do not change without the owner)

| Item | Value |
|---|---|
| NFT | Rifera Cursor Pieces, ERC721, symbol **RPIECE**, single contract |
| Pieces | **5, sequential per wallet**: 0 Pointer · 1 Ember · 2 Verdant · 3 Frost · 4 Void. 1 of each, max 5 per wallet (one complete set). No duplicates, no 6th mint |
| Supply cap | **1,111 per piece** (1,111 Pointer, 1,111 Ember, 1,111 Verdant, 1,111 Frost, 1,111 Void) — **5,555 total**. Enforced on-chain: minting a sold-out piece reverts (`PieceSoldOut`), and `nextMintQuote` reverts too. Per-piece caps are independent, but every wallet starts at Pointer, so once Pointer sells out no new wallet can start |
| Mint 1 (Pointer) | **FREE** (gas only) |
| Mint 2–5 | **0.002 BNB** each (Ember, Verdant, Frost, Void). Complete set = 0.008 BNB |
| Payment | **Exact only** — underpayment and overpayment both revert. Call `nextMintQuote(wallet)` first |
| Agent ID gate | wallet must hold a Binance Agent ID (`balanceOf > 0` at `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) — same gate as RiferaFirstTake / TalvioScanNFT |
| Mint gate | mint starts **CLOSED** (`mintOpen = false` at deploy). Owner opens with `setMintOpen(true)`, can close again any time |
| Money | **100% of paid mint BNB goes straight to the owner in the same transaction.** Nothing is kept in the contract. `withdraw()` exists only as a safety net for stuck dust |
| Mint open | mint starts **CLOSED** and is opened ONLY by the owner pressing the manual **Open Mint** button on the deploy page (step 03). Deploying never opens mint — not for RPIECE, not for staking |
| Staking | **RiferaCursorStake**: stake one complete set (exactly one of each piece; the 5 NFTs move into the staking contract and return in full on unstake). **Reward: 10% of the remaining pool per day**, split evenly between staked sets (MasterChef-style accRewardPerSet). Rewards accrue ONLY while at least one set is staked — with zero stakers the pool is untouched. A late staker earns only from distributions after they stake (no retroactive rewards) |
| Pool funding | **MANUAL ONLY** — anyone may call `fundPool()` (the owner is expected to fund it from mint proceeds). **No automatic split** from the mint contract (RPIECE was not changed for this). **No owner withdraw of the pool** — pool BNB leaves only via staker claims (`claim()` / `unstake()`). The stake contract owner has no privileged functions over the pool or anyone's NFTs |
| Art | fully on-chain SVG, deterministic per piece: Pointer sharp triangle (white), Ember jagged notched block (red), Verdant diagonal staircase (green), Frost widening wedge (blue), Void forked tail (purple). Different SHAPE per piece, not just colour, over a faint full-arrow silhouette |
| Old collection | RiferaFirstTake `0x0Cd348360109dd7f966B94a37Ff9BB0542b07Ec3` (7,620 takes) is a **separate collection** and stays as-is |

## Functions (verified selectors — see `forge test` / `cast sig`)

| Function | Selector | Notes |
|---|---|---|
| `mintedPerPiece(uint8)` | `0xb5368be0` | pieces minted of that type (0–1,111) |
| `remainingPerPiece(uint8)` | `0x5efaf243` | remaining supply of that piece (cap − minted) |
| `MAX_SUPPLY_PER_PIECE()` | `0x31e28d12` | 1,111 |
| `MAX_TOTAL_SUPPLY()` | `0x33039d3d` | 5,555 |
| `PieceSoldOut(uint8)` | `0x1870b764` | error selector, reverted when a piece type is sold out |
| `mint()` | `0x1249c58b` | payable, exact payment, mints next piece in order |
| `nextMintQuote(address)` | `0x50e3aeae` | exact price of next mint (0 / 0.002 BNB); reverts if complete |
| `pieceOf(uint256)` | `0xa8d514bc` | piece index 0–4 of a token |
| `piecesOf(address)` | `0x82e9f731` | piece indexes held, in mint order |
| `tokenIdsOf(address)` | `0xa3b261f2` | token ids held, in mint order |
| `hasCompleteSet(address)` | `0x88e08288` | true after all 5 |
| `totalMinted()` | `0xa2309ff8` | global minted count |
| `setMintOpen(bool)` | `0xf8004d31` | owner only |
| `tokenURI(uint256)` | `0xc87b56dd` | on-chain SVG data URI |
| `withdraw()` | `0x3ccfd60b` | owner only, safety net |
| `mintsByWallet(address)` | `0xd5353916` | pieces minted by a wallet (0–5) |
| `nextTokenId()` | `0x75794a3c` | next token id (starts at 1) |
| `mintOpen()` | `0x24bbd049` | |
| `agentId()` | `0xe84f43b7` | immutable registry address |

Selectors were verified with `cast sig` against this contract — never reuse a
selector from another project (lesson paid for 2026-11-22: Talvio's
`totalPrints()` was once given Rifera's `totalMinted()` selector).

## Staking — RiferaCursorStake (verified selectors)

| Function | Selector | Notes |
|---|---|---|
| `stake(uint256[5])` | `0x17c54c64` | tokenIds[0..4] = Pointer, Ember, Verdant, Frost, Void; caller must own all 5 + approve first; 1 set per wallet |
| `unstake()` | `0x2def6620` | returns all 5 NFTs + pays pending rewards in the same call |
| `claim()` | `0x4e71d92d` | pays pending rewards, keeps the stake; claiming 0 pays 0 (no revert) |
| `fundPool()` | `0x70f37d27` | payable, anyone may fund; funds start releasing from the next day |
| `stakedSets()` | `0xc1ca80cc` | sets currently staked (= totalStaked) |
| `stakedBy(address)` | `0x5f56a31a` | token ids staked by a wallet ([0,0,0,0,0] when not staked) |
| `pendingReward(address)` | `0xf40f0f52` | pending reward in wei (view, simulates daily releases) |
| `poolBalance()` | `0x96365d44` | pool BNB not yet released |
| `accRewardPerSet()` | `0x48a15c53` | cumulative reward per set, x1e18 |
| `hasStake(address)` | `0xe73e14bf` | |
| `rewardDebt(address)` | `0x5873eb9b` | acc at last settle, x1e18 |
| `claimable(address)` | `0x402914f5` | settled but unclaimed BNB (wei) |
| `totalStaked()` | `0x817b1cd2` | |
| `lastUpdate()` | `0xc0463711` | |
| `rpiece()` | `0x9c51f362` | immutable RPIECE address |
| `DAILY_RELEASE_BPS()` | `0xffc09552` | 1000 = 10% of remaining pool per day |
| `MAX_ACCRUAL_DAYS()` | `0xfe86a13a` | 365 — accrual cap per update call |
| `ACC_PRECISION()` | `0x32fcd966` | 1e18 |
| `onERC721Received(address,address,uint256,bytes)` | `0x150b7a02` | so safeTransferFrom into the contract works |
| `Staked(address,uint256[5])` | `0xe58bacee` | event |
| `Unstaked(address,uint256[5],uint256)` | `0xc6e7e6db` | event (rewardPaid) |
| `Claimed(address,uint256)` | `0xd8138f8a` | event |
| `PoolFunded(address,uint256)` | `0x32173d8e` | event |
| `AlreadyStaked(address)` | `0x0c45c8ec` | error |
| `NotStaked(address)` | `0x2449d29b` | error |
| `WrongPiece(uint256,uint8,uint8)` | `0xcc1c1cab` | error (tokenId, expected, actual) |
| `NotTokenOwner(uint256,address)` | `0x6d3d1858` | error (tokenId, actual owner) |
| `ZeroFund()` | `0x9ad19f1f` | error |
| `TransferFailed()` | `0x90b8ec18` | error |

Staking behaviour worth knowing:
- A staker's pending reward is `claimable + (accRewardPerSet − rewardDebt) / 1e18`.
  Sub-wei dust from the `/ 1e18` truncation stays in the contract (under 1 wei
  per settle) — negligible by design.
- `fundPool()` releases nothing for the funds just added on the same call:
  the daily release is always computed from the pool *before* the new funds,
  so new money starts earning for stakers from the next day.
- Unstaking while the pool is empty pays 0 reward and still returns the NFTs.
- The stake contract has **no withdraw function at all** — not for the pool,
  not for NFTs. Only `unstake()` (by the staker) can move NFTs out, and only
  `claim()` / `unstake()` (by the staker) can move pool BNB out.

## Structure

```
contracts/
  RiferaCursorPieces.sol   ERC721 + sequential mint + Agent ID gate + on-chain SVG
  RiferaCursorStake.sol    stake a complete set, 10%/day of remaining pool, manual fundPool, no owner pool withdraw
test/
  RiferaCursorPieces.t.sol 23 tests (quote, free/paid, order, reverts, complete set, SVG, withdraw, supply cap)
  RiferaCursorStake.t.sol  19 tests (stake success/reverts, 1-day 10% / 2-day 19%, claim, 2-staker split, late staker, unstake, no-staker pool untouched)
  MockAgentId.sol          mock Agent ID (tests only)
script/
  Deploy.s.sol             mainnet deploy (constructor arg = Agent ID registry)
  DeployStaking.s.sol      mainnet deploy staking (constructor args = PIECES_ADDRESS, deployer as owner)
deploy/
  RiferaCursorPieces.json  compiled ABI + creation bytecode (for the deploy page)
  RiferaCursorStake.json   compiled ABI + creation bytecode (for the deploy page)
export-deploy-artifacts.sh rebuilds + refreshes deploy/ from out/ (both contracts)
verify.sh                  one-command Sourcify verification (pieces, optionally + staking)
gen_deploy_page.py         generates the browser deploy page from deploy/
```

## Build & test

```shell
forge build
forge test   # 42 passed, 0 failed (23 RPIECE + 19 staking)
```

## Deploy (user only, own wallet + BNB)

```shell
export AGENT_ID=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
forge script script/Deploy.s.sol --rpc-url <BSC_RPC_URL> --broadcast --account <KEYSTORE>
```

Or use the browser deploy page (generated by `gen_deploy_page.py`):
`~/workspace/your_files/rifera-pieces/rifera-pieces-deploy.html`

After deploy the owner must open mint explicitly (mint starts closed):

```shell
cast send <PIECES_ADDRESS> "setMintOpen(bool)" true --rpc-url <BSC_RPC_URL> --account <KEYSTORE>
```

Then verify on Sourcify:

```shell
AGENT_ID=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F ./verify.sh <PIECES_ADDRESS>
```

Deploy staking (after RPIECE is deployed — staking does NOT open mint and
does NOT fund the pool):

```shell
PIECES_ADDRESS=<PIECES_ADDRESS> \
forge script script/DeployStaking.s.sol --rpc-url <BSC_RPC_URL> --broadcast --account <KEYSTORE>
```

Or use steps 07–08 on the browser deploy page. Then fund the pool manually
(anyone may fund; the owner is expected to fund it from mint proceeds):

```shell
cast send <STAKE_ADDRESS> "fundPool()" --value 1ether --rpc-url <BSC_RPC_URL> --account <KEYSTORE>
```

Verify staking on Sourcify (same script, extra args — constructor args are
the pieces address and the stake owner):

```shell
AGENT_ID=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F ./verify.sh <PIECES_ADDRESS> 56 <STAKE_ADDRESS> <STAKE_OWNER>
```

## Deploy artifacts (for the deploy page)

Refresh after every contract change — the deploy page must always use the
artifacts from the exact source that will be verified on Sourcify:

```shell
./export-deploy-artifacts.sh   # forge build + copy out/ -> deploy/
python3 gen_deploy_page.py     # regenerate the deploy page from deploy/
```

Then verify the page against BOTH `deploy/` AND `out/` (ABI + creation
bytecode exact equality). A page-vs-stale-artifact check proves nothing.
