// Concurrent load test for the read-only policy check used by TACo nodes.
// Run:  AMOY_RPC=<https url> GDM_ADDRESS=0x... TOKEN_ID=1 [BUYER=0x...] node stress_view.js
// Needs: npm i ethers   (v6, Node >= 18)

const fs = require("fs");
const { ethers } = require("ethers");

const abiFile = process.env.ABI || "./GDMRegistry.json";
const raw = JSON.parse(fs.readFileSync(abiFile, "utf8"));
const abi = Array.isArray(raw) ? raw : raw.abi;

const provider = new ethers.JsonRpcProvider(process.env.AMOY_RPC);
const gdm = new ethers.Contract(process.env.GDM_ADDRESS, abi, provider);
const TOKEN_ID = BigInt(process.env.TOKEN_ID || 1);
const BUYER = process.env.BUYER || ethers.Wallet.createRandom().address; // use a real purchaser to test the "allowed" path
const LEVELS = (process.env.LEVELS || "1,10,25,50,100").split(",").map(Number);
const TOTAL = Number(process.env.TOTAL || 300);

const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };

async function level(conc) {
    const lat = []; let fail = 0, started = 0; const errs = {};
    const t0 = performance.now();
    await Promise.all(Array.from({ length: conc }, async () => {
        while (started < TOTAL) {
        started++;
        const s = performance.now();
        try { await gdm.tacoCanDecrypt(TOKEN_ID, BUYER); lat.push(performance.now() - s); }
        catch (e) { fail++; const k = (e.code || e.shortMessage || "error").toString().slice(0, 60); errs[k] = (errs[k] || 0) + 1; }
        }
    }));
    const sec = (performance.now() - t0) / 1000;
    const row = { concurrency: conc, ok: lat.length, fail, req_per_s: +(TOTAL / sec).toFixed(1),
        p50_ms: lat.length ? Math.round(pct(lat, .5)) : null, p95_ms: lat.length ? Math.round(pct(lat, .95)) : null,
        p99_ms: lat.length ? Math.round(pct(lat, .99)) : null };
    console.log(row, Object.keys(errs).length ? errs : "");
    return row;
}

(async () => {
    for (let i = 0; i < 20; i++) await gdm.tacoCanDecrypt(TOKEN_ID, BUYER); // warm-up
    const rows = [];
    for (const c of LEVELS) rows.push(await level(c));
    const head = Object.keys(rows[0]).join(",");
    fs.writeFileSync("stress_view_results.csv", [head, ...rows.map(r => Object.values(r).join(","))].join("\n"));
    console.log("saved stress_view_results.csv");
})();
