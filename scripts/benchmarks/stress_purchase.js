// Many buyers call purchaseFullAccess at once on a LOCAL Hardhat node.
// Prereq: contracts deployed and one SGD registered (reuse your deploy/test setup).
// Run:  npx hardhat node            (terminal 1)
//       GDM_ADDRESS=0x... TOKEN_ID=1 BUYERS=50 npx hardhat run scripts/stress_purchase.js --network localhost
// Optional: MINING=interval  -> mines one block every 2 s so transactions really compete inside blocks.

const { ethers } = require("hardhat");

const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };

async function main() {
    const gdm = await ethers.getContractAt("GDMRegistry", process.env.GDM_ADDRESS);
    const tokenId = BigInt(process.env.TOKEN_ID || 1);
    const N = Number(process.env.BUYERS || 50);
    const rec = await gdm.getFullRecord(tokenId);
    const price = rec.price;
    const sgd = await ethers.getContractAt("SGDNFT", await gdm.sgdNft());
    const seller = await sgd.ownerOf(tokenId);
    const feeReceiver = await gdm.feeReceiver();
    const feeBps = await gdm.platformFeePercentage();

    if (process.env.MINING === "interval") {
        await ethers.provider.send("evm_setAutomine", [false]);
        await ethers.provider.send("evm_setIntervalMining", [2000]);
    }

    const buyers = Array.from({ length: N }, () => ethers.Wallet.createRandom().connect(ethers.provider));
    for (const b of buyers)
        await ethers.provider.send("hardhat_setBalance", [b.address, "0x" + (10n ** 20n).toString(16)]);

    const sellerBefore = await ethers.provider.getBalance(seller);
    const feeBefore = await ethers.provider.getBalance(feeReceiver);

    const lat = [], gas = []; let fail = 0; const errs = {};
    const t0 = performance.now();
    await Promise.all(buyers.map(async (b) => {
        const s = performance.now();
        try {
        const tx = await gdm.connect(b).purchaseFullAccess(tokenId, { value: price });
        const rc = await tx.wait();
        lat.push(performance.now() - s); gas.push(Number(rc.gasUsed));
        } catch (e) { fail++; const k = (e.shortMessage || e.message).slice(0, 70); errs[k] = (errs[k] || 0) + 1; }
    }));
    const sec = (performance.now() - t0) / 1000;

    let purchased = 0;
    for (const b of buyers) if (await gdm.hasPurchased(tokenId, b.address)) purchased++;
    const sellerGain = (await ethers.provider.getBalance(seller)) - sellerBefore;
    const feeGain = (await ethers.provider.getBalance(feeReceiver)) - feeBefore;
    const okN = BigInt(lat.length);
    const expectedFee = (price * feeBps / 10000n) * okN;

    console.log({ buyers: N, ok: lat.length, fail, purchased_flags: purchased, tx_per_s: +(N / sec).toFixed(1),
        p50_ms: lat.length ? Math.round(pct(lat, .5)) : null, p95_ms: lat.length ? Math.round(pct(lat, .95)) : null,
        avg_gas: gas.length ? Math.round(gas.reduce((a, b) => a + b, 0) / gas.length) : null });
    console.log({ fee_matches: feeGain === expectedFee, seller_matches: sellerGain === (price * okN - expectedFee) });
    if (Object.keys(errs).length) console.log("errors:", errs);
    if (process.env.MINING === "interval") await ethers.provider.send("evm_setAutomine", [true]);
}

main().catch((e) => { console.error(e); process.exit(1); });
