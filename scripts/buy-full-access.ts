import fs from "fs";
import path from "path";
import "dotenv/config";
import { ethers } from "ethers";

const addressesPath = path.resolve(
    process.cwd(),
    "../server/src/config/contract-addresses.json"
);

const artifactPath = path.resolve(
    process.cwd(),
    "artifacts/contracts/GDMNFT.sol/GDMRegistry.json"
);

async function main() {
    const tokenId = Number(process.env.TOKEN_ID || "1");

    if (Number.isNaN(tokenId)) {
        throw new Error("TOKEN_ID is invalid in .env");
    }

    const rpcUrl = process.env.RPC_URL;
    const buyerPrivateKey = process.env.BUYER_PRIVATE_KEY;

    if (!rpcUrl) {
        throw new Error("Missing RPC_URL in .env");
    }

    if (!buyerPrivateKey) {
        throw new Error("Missing BUYER_PRIVATE_KEY in .env");
    }

    const addresses = JSON.parse(fs.readFileSync(addressesPath, "utf8"));
    const registryArtifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));

    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const buyer = new ethers.Wallet(buyerPrivateKey, provider);

    const registry = new ethers.Contract(
        addresses.GDMREGISTRY_ADDRESS,
        registryArtifact.abi,
        buyer
    );

    const publicRecord = await registry.getPublicRecord(tokenId);
    const price = publicRecord.price;

    console.log("Buyer:", buyer.address);
    console.log("Token ID:", tokenId);
    console.log("Price:", price.toString());

    const tx = await registry.purchaseFullAccess(tokenId, { value: price });
    await tx.wait();

    console.log(`Buyer ${buyer.address} purchased access for tokenId=${tokenId}`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});