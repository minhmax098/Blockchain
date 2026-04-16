// API /request-key 
// verify signature, check hasPurchased, return key/iv if valid
// API:  
// POST /auth/challenge  
// POST /request-key
import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import { ethers } from "ethers";
import { hasPurchased } from "./blockchain.js";

dotenv.config();

type KeyRecord = {
    sgdId: string;
    tokenId: number | null;
    cid: string;
    key: string;
    iv: string;
    authTag: string;
    originalFilename: string;
    encryptedFilename: string;
};

type KeyStore = {
    records: KeyRecord[];
};

const app = express();
app.use(cors());
app.use(express.json());

const port = Number(process.env.BACKEND_PORT || 3001);
const keyStorePath = path.join(__dirname, "keyStore.json");

const challenges = new Map<string, string>();

function loadKeyStore(): KeyStore {
    return JSON.parse(fs.readFileSync(keyStorePath, "utf8"));
}

app.get("/health", (_req, res) => {
    res.json({ ok: true });
});

app.post("/auth/challenge", (req, res) => {
    const { address, tokenId } = req.body as { address?: string; tokenId?: number };

    if (!address || !tokenId) {
        return res.status(400).json({ error: "address and tokenId are required" });
    }

    const nonce = crypto.randomBytes(16).toString("hex");
    const message = `Request decryption key for tokenId ${tokenId}. Nonce: ${nonce}`;

    challenges.set(address.toLowerCase(), message);
    return res.json({ message });
});

app.post("/request-key", async (req, res) => {
    try {
        const { address, tokenId, signature } = req.body as {
            address?: string;
            tokenId?: number;
            signature?: string;
        };

        if (!address || !tokenId || !signature) {
            return res.status(400).json({ error: "address, tokenId, signature are required" });
        }

        const expectedMessage = challenges.get(address.toLowerCase());
        if (!expectedMessage) {
            return res.status(400).json({ error: "No challenge found for this address" });
        }

        const recovered = ethers.verifyMessage(expectedMessage, signature);
        if (recovered.toLowerCase() !== address.toLowerCase()) {
            return res.status(401).json({ error: "Invalid signature" });
        }

        const purchased = await hasPurchased(tokenId, address);
        if (!purchased) {
            return res.status(403).json({ error: "Access not purchased" });
        }

        const store = loadKeyStore();
        const record = store.records.find((r) => r.tokenId === tokenId);

        if (!record) {
            return res.status(404).json({ error: "Key record not found" });
        }

        challenges.delete(address.toLowerCase());

        return res.json({
            cid: record.cid,
            key: record.key,
            iv: record.iv,
            authTag: record.authTag,
            originalFilename: record.originalFilename,
            encryptedFilename: record.encryptedFilename,
        });
    } catch (error) {
        console.error(error);
        return res.status(500).json({ error: "Internal server error" });
    }
});

app.listen(port, () => {
    console.log(`Backend listening on http://localhost:${port}`);
});