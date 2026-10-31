// MODEL, not a network test: client waits for t valid replies out of n TACo nodes while f nodes fail.
// Run:  node fault_sim.js [--n 7] [--t 4] [--trials 20000] [--timeout 3000] [--target-ms 425]
// Replace sampleNodeMs() with your MEASURED per-node latencies for a more honest result.

const arg = (k, d) => { const i = process.argv.indexOf("--" + k); return i > -1 ? Number(process.argv[i + 1]) : d; };
const n = arg("n", 7), t = arg("t", 4), trials = arg("trials", 20000), timeout = arg("timeout", 3000), target = arg("target-ms", 425);

const rnd = () => Math.random();
const gauss = (m, s) => m + s * Math.sqrt(-2 * Math.log(1 - rnd())) * Math.cos(2 * Math.PI * rnd());
// Default per-node response time: network round trip U(45,180) ms (range in the paper) + view check N(122,14) ms.
const sampleNodeMs = () => 45 + 135 * rnd() + Math.max(1, gauss(122, 14));

const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };

function once(f, mode, offset) {
    const idx = [...Array(n).keys()].sort(() => rnd() - 0.5);
    const bad = new Set(idx.slice(0, f));
    const replies = [];
    for (let i = 0; i < n; i++) {
        let ms = sampleNodeMs();
        if (bad.has(i)) {
        if (mode === "crash" || mode === "malformed") continue;   // no valid share ever arrives
        if (mode === "slow") ms += 5000;                          // arrives after the timeout
        }
        replies.push(ms);
    }
    replies.sort((a, b) => a - b);
    if (replies.length < t) return null;
    const done = replies[t - 1] + offset;
    return done <= timeout ? done : null;
}

for (const mode of ["crash", "slow"]) {
    // calibrate a constant offset so that the fault-free median equals the measured key-release latency
    const base = Array.from({ length: 5000 }, () => once(0, mode, 0));
    const offset = target - pct(base, 0.5);
    console.log(`\nmode=${mode}  n=${n} t=${t}  timeout=${timeout} ms  offset=${offset.toFixed(0)} ms  (model, calibrated to ${target} ms at f=0)`);
    console.log("f\tsuccess%\tp50_ms\tp95_ms");
    for (let f = 0; f <= n; f++) {
        const ok = []; let succ = 0;
        for (let k = 0; k < trials; k++) { const r = once(f, mode, offset); if (r !== null) { succ++; ok.push(r); } }
        console.log(`${f}\t${(100 * succ / trials).toFixed(1)}\t\t${ok.length ? Math.round(pct(ok, .5)) : "-"}\t${ok.length ? Math.round(pct(ok, .95)) : "-"}`);
    }
}

console.log(`\nExpected: success=100% while f <= n - t = ${n - t}; 0% beyond.`);
