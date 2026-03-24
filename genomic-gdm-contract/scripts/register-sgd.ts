// call registerSGD(...)
// attach the newly created CID to the chain

import { network } from "hardhat";
import fs from "fs";
import path from "path";

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

const keyStorePath = path.join(__dirname, "..", "backend", "keyStore.json");

function loadKeyStore(): KeyStore {
    return JSON.parse(fs.readFileSync(keyStorePath, "utf8"));
}

function saveKeyStore(data: KeyStore) {
    fs.writeFileSync(keyStorePath, JSON.stringify(data, null, 2));
}

async function main() {
    const { ethers } = await network.connect();
    const sgdId = process.argv[2] || "SGD-0001";

    const addresses = JSON.parse(
        fs.readFileSync(path.join(__dirname, "..", "backend", "contract-addresses.json"), "utf8")
    );

    const store = loadKeyStore();
    const record = store.records.find((r) => r.sgdId === sgdId);

    if (!record) {
        throw new Error(`No keyStore record found for sgdId=${sgdId}`);
    }

    const [registrar, initialOwner] = await ethers.getSigners();

    const registry = await ethers.getContractAt("GDMRegistry", addresses.GDMREGISTRY_ADDRESS, registrar);

    const nextId = await registry.nextTokenId();

    const input = {
        initialOwner: initialOwner.address,
        sgdId: record.sgdId,
        rgdId: `RGD-${record.sgdId}`,
        cid: record.cid,
        accessCondition: "paid full access",
        price: ethers.parseEther("0.01"),
        collectionDate: Math.floor(Date.now() / 1000),
        sampleType: "blood",
        patientRef: "PATIENT-DEMO-001",
        consentCode: "CONSENT-DEMO",
        sampleHash: ethers.keccak256(ethers.toUtf8Bytes(record.originalFilename)),
        encryptionScheme: "AES-256-GCM",
        sequencingInfo: "demo-sequencing-info",
        signatureRef: "demo-signature-ref",
        encHash: ethers.keccak256(ethers.toUtf8Bytes(record.cid)),
        tokenURI: "",
    };

    const tx = await registry.registerSGD(input);
    await tx.wait();

    record.tokenId = Number(nextId);
    saveKeyStore(store);

    console.log(`Registered SGD ${record.sgdId} with tokenId=${record.tokenId}`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});