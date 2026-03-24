// download ciphertext from IPFS
// Use the /iv key to decrypt locally
import axios from "axios";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { ethers } from "ethers";
import dotenv from "dotenv";

dotenv.config();

async function main() {
    const tokenId = Number(process.argv[2] || "1");
    const buyerKey = process.env.BUYER_PRIVATE_KEY;

    if (!buyerKey) {
        throw new Error("BUYER_PRIVATE_KEY missing in .env");
    }

    const wallet = new ethers.Wallet(buyerKey);
    const backendBase = `http://localhost:${process.env.BACKEND_PORT || 3001}`;
    const gateway = process.env.IPFS_GATEWAY || "https://gateway.pinata.cloud/ipfs";

    const challengeRes = await axios.post(`${backendBase}/auth/challenge`, {
        address: wallet.address,
        tokenId,
    });

    const message = challengeRes.data.message;
    const signature = await wallet.signMessage(message);

    const keyRes = await axios.post(`${backendBase}/request-key`, {
        address: wallet.address,
        tokenId,
        signature,
    });

    const { cid, key, iv, authTag, originalFilename } = keyRes.data;

    const fileRes = await axios.get(`${gateway}/${cid}`, {
        responseType: "arraybuffer",
    });

    const encryptedData = Buffer.from(fileRes.data);
    const decipher = crypto.createDecipheriv(
        "aes-256-gcm",
        Buffer.from(key, "base64"),
        Buffer.from(iv, "base64")
    );

    decipher.setAuthTag(Buffer.from(authTag, "base64"));

    const decrypted = Buffer.concat([
        decipher.update(encryptedData),
        decipher.final(),
    ]);

    const outDir = path.join(__dirname, "..", "downloads");
    if (!fs.existsSync(outDir)) {
        fs.mkdirSync(outDir, { recursive: true });
    }

    const outPath = path.join(outDir, `decrypted-${originalFilename}`);
    fs.writeFileSync(outPath, decrypted);

    console.log("Decrypted file saved to:", outPath);
    console.log("Content preview:");
    console.log(decrypted.toString("utf8"));
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});