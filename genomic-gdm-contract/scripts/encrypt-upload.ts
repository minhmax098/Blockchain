// Read original file, AES encrypt
// upload .enc to IPFS and save the key /iv/cid to BE store
import fs from "fs";
import path from "path";
import crypto from "crypto";
import axios from "axios";
import FormData from "form-data";
import dotenv from "dotenv";

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

const uploadsDir = path.join(__dirname, "..", "uploads");
const encryptedDir = path.join(__dirname, "..", "encrypted");
const keyStorePath = path.join(__dirname, "..", "backend", "keyStore.json");

function loadKeyStore(): KeyStore {
    if (!fs.existsSync(keyStorePath)) {
        return { records: [] };
    }
    return JSON.parse(fs.readFileSync(keyStorePath, "utf8"));
}

function saveKeyStore(data: KeyStore) {
    fs.writeFileSync(keyStorePath, JSON.stringify(data, null, 2));
}

async function uploadToPinata(filePath: string): Promise<string> {
    const jwt = process.env.PINATA_JWT;
    if (!jwt) {
        throw new Error("PINATA_JWT missing in .env");
    }

    const form = new FormData();
    form.append("file", fs.createReadStream(filePath));

    const res = await axios.post("https://api.pinata.cloud/pinning/pinFileToIPFS", form, {
        maxBodyLength: Infinity,
        headers: {
        ...form.getHeaders(),
        Authorization: `Bearer ${jwt}`,
        },
    });

    return res.data.IpfsHash;
}

async function main() {
    const filename = process.argv[2] || "sample.txt";
    const sgdId = process.argv[3] || `SGD-${Date.now()}`;

    const inputPath = path.join(uploadsDir, filename);
    if (!fs.existsSync(inputPath)) {
        throw new Error(`File not found: ${inputPath}`);
    }

    if (!fs.existsSync(encryptedDir)) {
        fs.mkdirSync(encryptedDir, { recursive: true });
    }

    const plaintext = fs.readFileSync(inputPath);

    const key = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);

    const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
    const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const authTag = cipher.getAuthTag();

    const encryptedFilename = `${filename}.enc`;
    const encryptedPath = path.join(encryptedDir, encryptedFilename);
    fs.writeFileSync(encryptedPath, encrypted);

    const cid = await uploadToPinata(encryptedPath);

    const store = loadKeyStore();
    store.records.push({
        sgdId,
        tokenId: null,
        cid,
        key: key.toString("base64"),
        iv: iv.toString("base64"),
        authTag: authTag.toString("base64"),
        originalFilename: filename,
        encryptedFilename,
    });

    saveKeyStore(store);

    console.log("Encrypted file:", encryptedPath);
    console.log("CID:", cid);
    console.log("Saved record for sgdId:", sgdId);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});