import { network } from "hardhat";
import { ethers as ethersLib } from "ethers";
import fs from "fs";
import path from "path";
import "dotenv/config";

const addressesPath = path.resolve(
    process.cwd(),
    "../server/src/config/contract-addresses.json"
);

async function main() {
    const { ethers } = await network.connect();
    const tokenId = Number(process.argv[2] || "1");

    const addresses = JSON.parse(fs.readFileSync(addressesPath, "utf8"));

    const rpcUrl = process.env.RPC_URL;
    const buyerPrivateKey = process.env.BUYER_PRIVATE_KEY;

    if (!rpcUrl) {
        throw new Error("Missing RPC_URL in .env");
    }

    if (!buyerPrivateKey) {
        throw new Error("Missing BUYER_PRIVATE_KEY in .env");
    }

    const provider = new ethersLib.JsonRpcProvider(rpcUrl);
    const buyer = new ethersLib.Wallet(buyerPrivateKey, provider);

    const registryArtifactPath = path.resolve(
        process.cwd(),
        "artifacts/contracts/GDMNFT.sol/GDMRegistry.json"
    );

    const registryArtifact = JSON.parse(
        fs.readFileSync(registryArtifactPath, "utf8")
    );

    const registry = new ethersLib.Contract(
        addresses.GDMREGISTRY_ADDRESS,
        registryArtifact.abi,
        buyer
    );

    const publicRecord = await registry.getPublicRecord(tokenId);
    const price = publicRecord.price;

    const tx = await registry.purchaseFullAccess(tokenId, { value: price });
    await tx.wait();

    console.log(`Buyer ${buyer.address} purchased access for tokenId=${tokenId}`);
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});