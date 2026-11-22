#!/usr/bin/env python3
"""Generate ~/workspace/your_files/rifera-pieces/rifera-pieces-deploy.html
from the FRESH forge artifacts in ~/workspace/rifera-pieces/deploy/.

RULE (paid for with real losses): deploy/*.json must be refreshed from out/
BEFORE running this script, and the generated page must then be verified
against BOTH deploy/ AND out/ (ABI + creation bytecode exact).
"""
import json, pathlib

BASE = pathlib.Path("/home/hatch/workspace/rifera-pieces")
OUT = pathlib.Path("/home/hatch/workspace/your_files/rifera-pieces/rifera-pieces-deploy.html")

def art(name):
    d = json.load(open(BASE / "deploy" / f"{name}.json"))
    return {"abi": d["abi"], "bytecode": d["bytecode"]["object"]}

PIECES = art("RiferaCursorPieces")

TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Rifera Cursor Pieces — Deploy</title>
<script src="https://cdn.jsdelivr.net/npm/ethers@6.13.2/dist/ethers.umd.min.js"></script>
<style>
  :root { --bg:#050505; --card:#0d0d0d; --line:#1f1f1f; --ink:#e8e8e8; --soft:#9a9a9a; --accent:#F2B705; }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif; }
  .wrap { max-width:780px; margin:0 auto; padding:28px 18px 60px; }
  h1 { font-size:1.6rem; margin:6px 0 4px; font-family:ui-monospace,Menlo,Consolas,monospace; letter-spacing:.02em; }
  .sub { color:var(--soft); margin:0 0 20px; line-height:1.55; }
  .step { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:18px; margin:14px 0; }
  .step h2 { margin:0 0 8px; font-size:1.1rem; font-family:ui-monospace,Menlo,Consolas,monospace; }
  .step h2 .n { color:var(--accent); margin-right:8px; }
  .step p { color:var(--soft); line-height:1.55; margin:8px 0; }
  .step p b, .step li b { color:var(--ink); }
  ul { color:var(--soft); line-height:1.6; margin:8px 0; padding-left:20px; }
  .btn { background:var(--accent); color:#050505; border:0; border-radius:8px; padding:11px 18px; font-weight:700; font-size:1rem; cursor:pointer; margin:6px 8px 0 0; font-family:ui-monospace,Menlo,Consolas,monospace; }
  .btn.green { background:#4ade80; }
  .btn.ghost { background:transparent; border:1px solid var(--accent); color:var(--ink); }
  .btn:disabled { opacity:.4; cursor:not-allowed; }
  .mono { font-family:ui-monospace,Menlo,Consolas,monospace; word-break:break-all; }
  .pill { display:inline-block; font-size:.8rem; font-weight:700; padding:3px 10px; border-radius:999px; background:#333; color:#fff; vertical-align:middle; font-family:ui-monospace,Menlo,Consolas,monospace; }
  .pill.live { background:#4ade80; color:#050505; }
  .pill.done { background:#555; }
  .pill.warn { background:#b45309; }
  #log { background:#000; border:1px solid var(--line); border-radius:10px; padding:14px; font-family:ui-monospace,Menlo,Consolas,monospace; font-size:.85rem; line-height:1.6; white-space:pre-wrap; word-break:break-word; min-height:80px; }
  #log .ok { color:#4ade80; } #log .err { color:#f87171; }
  .kv { background:#000; border:1px solid var(--line); border-radius:10px; padding:12px 14px; margin:10px 0; line-height:1.9; font-family:ui-monospace,Menlo,Consolas,monospace; font-size:.88rem; white-space:pre-wrap; }
  input[type=text] { width:100%; background:#000; color:var(--ink); border:1px solid var(--line); border-radius:8px; padding:10px 12px; font-family:ui-monospace,Menlo,Consolas,monospace; font-size:.85rem; }
  label { display:block; font-size:.85rem; color:var(--soft); margin-bottom:4px; }
  .cash { border:1px solid #4ade80; }
  pre.prompt { background:#000; border:1px solid var(--line); border-radius:10px; padding:12px 14px; font-family:ui-monospace,Menlo,Consolas,monospace; font-size:.85rem; line-height:1.6; white-space:pre-wrap; }
</style>
</head>
<body>
<div class="wrap">
  <h1>RIFERA CURSOR PIECES — DEPLOY</h1>
  <p class="sub">Owner-only page. Deploy the Rifera Cursor Pieces NFT (RPIECE) on BNB Chain: 5 sequential pieces — Pointer, Ember, Verdant, Frost, Void — that build one First Cursor. Nothing here deploys or moves funds without your wallet confirmation. <b>Do NOT deploy twice:</b> one contract, one set of pieces.</p>

  <section class="step cash">
    <h2><span class="n">$</span>Cash math</h2>
    <ul>
      <li><b>1 complete set = 0.008 BNB</b> to the project wallet: piece 1 (Pointer) <b>FREE</b>, pieces 2–5 <b>0.002 BNB each</b>.</li>
      <li><b>100% of paid mint BNB goes straight to the owner in the same transaction.</b> Nothing is kept in the contract (withdraw() exists only as a safety net for stuck dust).</li>
      <li>Payment must be <b>exact</b> — underpayment and overpayment both revert. Always call <b>nextMintQuote(wallet)</b> first.</li>
      <li>Max <b>5 pieces per wallet</b> (one complete set, one of each, in order). No 6th mint, no duplicates.</li>
    </ul>
  </section>

  <section class="step" id="step-connect">
    <h2><span class="n">01</span>Connect wallet</h2>
    <p>Connect the wallet that should <b>own</b> the contract. It deploys it and receives all paid mint BNB. Must be on <b>BNB Chain (chain 56)</b>.</p>
    <button class="btn" id="btn-connect" type="button">Connect Wallet</button>
    <button class="btn" id="btn-copy-link" type="button">Copy page link</button>
    <p id="wallet-status">Not connected.</p>
    <p class="sub">Browser biasa (Chrome / Telegram) tidak punya wallet — tombol Connect tidak akan bisa jalan dari sana. Buka link halaman ini di dalam aplikasi wallet (MetaMask, Trust Wallet, OKX, atau Binance Wallet — menu Browser / dApp), lalu tekan Connect Wallet di sana.</p>
  </section>

  <section class="step" id="step-deploy">
    <h2><span class="n">02</span>Deploy RiferaCursorPieces (RPIECE) <span class="pill done" id="pill-deploy">Not deployed</span></h2>
    <p>Single ERC721 contract, name <b>Rifera Cursor Pieces</b>, symbol <b>RPIECE</b>. Constructor argument is fixed and read-only:</p>
    <p><label>Binance Agent ID registry (fixed, cannot be changed)</label><input class="mono" type="text" readonly value="0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F" /></p>
    <ul>
      <li><b>Agent ID required for every mint</b> — free or paid (same gate as RiferaFirstTake).</li>
      <li><b>Sequential mint:</b> Pointer (free) → Ember → Verdant → Frost → Void (0.002 BNB each).</li>
      <li><b>On-chain SVG art:</b> each piece is a different pixel shard of the Rifera arrow cursor — Pointer sharp triangle (white), Ember jagged notched block (red), Verdant diagonal staircase (green), Frost widening wedge (blue), Void forked tail (purple).</li>
    </ul>
    <button class="btn" id="btn-deploy" type="button" disabled>Deploy RiferaCursorPieces</button>
    <p>Pieces contract: <span class="mono" id="pieces-addr">—</span></p>
    <p><label>Already deployed? Paste the contract address to resume</label><input id="in-pieces" class="mono" type="text" placeholder="0x..." /></p>
    <button class="btn ghost" id="btn-use-pieces" type="button" disabled>Use this contract address</button>
  </section>

  <section class="step" id="step-open">
    <h2><span class="n">03</span>Open mint <span class="pill done" id="pill-open">Mint closed</span></h2>
    <p>Mint starts <b>CLOSED</b> at deploy. Open it with <b>setMintOpen(true)</b> when you are ready. You can close it again any time with the same function (owner only).</p>
    <button class="btn green" id="btn-open" type="button" disabled>Open Mint (setMintOpen(true))</button>
    <p id="open-status">Deploy the contract first.</p>
  </section>

  <section class="step" id="step-status">
    <h2><span class="n">04</span>Verify on-chain <span class="pill done" id="pill-verify">Not verified</span></h2>
    <p>Read the live state and confirm it matches the spec: name/symbol, Agent ID registry, mint open, totalMinted.</p>
    <button class="btn green" id="btn-refresh" type="button" disabled>Refresh Status</button>
    <div class="kv" id="live-status">Deploy the contract first.</div>
  </section>

  <section class="step">
    <h2><span class="n">05</span>Agent mint prompt (4 lines)</h2>
    <p>Copy this prompt for a mint. The agent must call <b>nextMintQuote(wallet)</b> first, then <b>mint()</b> with exactly that value.</p>
    <pre class="prompt">Mint the next Rifera Cursor Piece now.
Contract: __PIECES_ADDR__ on BNB Chain (56), function mint() payable.
First check nextMintQuote(my wallet), then send exactly that value (0 for Pointer, 0.002 BNB after).
Agent ID required. Reply with the tx link only.</pre>
    <p class="sub">Replace __PIECES_ADDR__ with the deployed contract address from step 02 after you deploy.</p>
  </section>

  <section class="step">
    <h2><span class="n">06</span>After deploy</h2>
    <ul>
      <li>Verify the contract on BscScan / Sourcify (solc 0.8.24, optimizer 200, evm cancun, constructor arg = Agent ID registry above). In this repo: <b>./verify.sh &lt;PIECES_ADDRESS&gt;</b></li>
      <li>Put the deployed address into the Rifera Game web (artifact rifera-game): Pieces section, Marketplace Buy, and the agent prompt.</li>
      <li>The old RiferaFirstTake NFT (0x0Cd348360109dd7f966B94a37Ff9BB0542b07Ec3, 7,620 takes) is a <b>separate collection</b> and stays as-is. Do not wire pieces to it.</li>
      <li>No funding step, no claim pool, no LP pairing in this contract — paid mint BNB goes to the owner immediately.</li>
    </ul>
  </section>

  <div id="log">Log ready.</div>
</div>

<script>
const ART_PIECES = __ART_PIECES__;
const REGISTRY = "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F";

const $ = (id) => document.getElementById(id);
let provider = null, signer = null, account = null;
let piecesAddr = null;

function log(msg, cls) {
  const el = $("log");
  const line = document.createElement("div");
  if (cls) line.className = cls;
  line.textContent = msg;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
}
function setPill(id, text, cls) {
  const p = $(id);
  p.textContent = text;
  p.className = "pill" + (cls ? " " + cls : "");
}
function isAddr(v) { return /^0x[0-9a-fA-F]{40}$/.test(v || ""); }

async function connect() {
  if (typeof ethers === "undefined") { $("wallet-status").textContent = "Wallet library failed to load — check your connection and reload the page."; log("ethers library missing (CDN failed).", "err"); return; }
  if (!window.ethereum) { $("wallet-status").textContent = "No wallet found. Open this page inside a wallet app browser (MetaMask / Trust Wallet / OKX / Binance Wallet)."; log("window.ethereum missing.", "err"); return; }
  try {
    provider = new ethers.BrowserProvider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    const net = await provider.getNetwork();
    if (net.chainId !== 56n) {
      try {
        await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x38" }] });
      } catch (e) {
        await window.ethereum.request({ method: "wallet_addEthereumChain", params: [{ chainId: "0x38", chainName: "BNB Smart Chain", nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 }, rpcUrls: ["https://bsc-dataseed.binance.org/"], blockExplorerUrls: ["https://bscscan.com/"] }] });
      }
    }
    signer = await provider.getSigner();
    account = await signer.getAddress();
    $("wallet-status").textContent = "Connected: " + account + " (BNB Chain)";
    log("Connected: " + account, "ok");
    $("btn-deploy").disabled = false;
    $("btn-use-pieces").disabled = false;
  } catch (e) {
    $("wallet-status").textContent = "Connect failed: " + (e && e.message ? e.message : e);
    log("Connect failed: " + (e && e.message ? e.message : e), "err");
  }
}

async function deployPieces() {
  $("btn-deploy").disabled = true;
  try {
    const f = new ethers.ContractFactory(ART_PIECES.abi, ART_PIECES.bytecode, signer);
    log("Deploying RiferaCursorPieces ... (confirm in wallet)");
    const c = await f.deploy(REGISTRY);
    log("Deploy tx: " + c.deploymentTransaction().hash);
    await c.waitForDeployment();
    piecesAddr = await c.getAddress();
    $("pieces-addr").textContent = piecesAddr;
    setPill("pill-deploy", "Deployed", "live");
    log("RiferaCursorPieces deployed: " + piecesAddr, "ok");
    $("btn-open").disabled = false;
    $("btn-refresh").disabled = false;
    $("open-status").textContent = "Mint is closed. Open it when ready.";
  } catch (e) { log("Deploy failed: " + (e && e.message ? e.message : e), "err"); $("btn-deploy").disabled = false; }
}

async function openMint() {
  if (!piecesAddr) { log("Deploy the contract first.", "err"); return; }
  $("btn-open").disabled = true;
  try {
    const c = new ethers.Contract(piecesAddr, ART_PIECES.abi, signer);
    log("Opening mint ... (confirm in wallet)");
    const tx = await c.setMintOpen(true);
    log("setMintOpen tx: " + tx.hash);
    await tx.wait();
    setPill("pill-open", "Mint open", "live");
    $("open-status").textContent = "Mint is OPEN.";
    log("Mint is open.", "ok");
  } catch (e) { log("Open mint failed: " + (e && e.message ? e.message : e), "err"); $("btn-open").disabled = false; }
}

async function refresh() {
  if (!piecesAddr) { $("live-status").textContent = "Deploy the contract first."; return; }
  try {
    const c = new ethers.Contract(piecesAddr, ART_PIECES.abi, provider);
    const lines = [
      "Name: " + await c.name() + " (" + await c.symbol() + ")",
      "Agent ID registry: " + await c.agentId() + " (want " + REGISTRY + ")",
      "Mint open: " + await c.mintOpen(),
      "totalMinted: " + await c.totalMinted(),
      "nextTokenId: " + await c.nextTokenId(),
      "Owner: " + await c.owner(),
      "Contract balance: " + ethers.formatEther(await provider.getBalance(piecesAddr)) + " BNB (want 0 — paid mints forward to owner)",
    ];
    $("live-status").textContent = lines.join("\n");
    const ok = (await c.name()) === "Rifera Cursor Pieces" && (await c.symbol()) === "RPIECE" && (await c.agentId()).toLowerCase() === REGISTRY.toLowerCase();
    setPill("pill-verify", ok ? "Verified" : "Check numbers", ok ? "live" : "warn");
    log(ok ? "On-chain state matches the spec." : "On-chain state does NOT match — check the numbers above.", ok ? "ok" : "err");
  } catch (e) { log("Refresh failed: " + (e && e.message ? e.message : e), "err"); }
}

function useAddr() {
  const v = $("in-pieces").value.trim();
  if (!isAddr(v)) { log("Invalid address.", "err"); return; }
  piecesAddr = v;
  $("pieces-addr").textContent = v;
  setPill("pill-deploy", "Set", "live");
  $("btn-open").disabled = false;
  $("btn-refresh").disabled = false;
  $("open-status").textContent = "Mint state unknown — press Refresh Status, then Open Mint if closed.";
  log("Contract set: " + v, "ok");
}

$("btn-connect").addEventListener("click", connect);
$("btn-copy-link").addEventListener("click", () => { navigator.clipboard.writeText(location.href).then(() => log("Page link copied.", "ok")); });
$("btn-deploy").addEventListener("click", deployPieces);
$("btn-open").addEventListener("click", openMint);
$("btn-refresh").addEventListener("click", refresh);
$("btn-use-pieces").addEventListener("click", useAddr);
</script>
</body>
</html>
"""

html = TEMPLATE.replace("__ART_PIECES__", json.dumps(PIECES))
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(html)
print("wrote", OUT, len(html), "bytes")
