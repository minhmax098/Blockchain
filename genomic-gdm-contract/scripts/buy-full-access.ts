// buyer can access full record 
import { network } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    const { ethers } = await network.connect();
    const tokenId = Number(process.argv[2] || "1");

    const addresses = JSON.parse(
        fs.readFileSync(path.join(__dirname, "..", "backend", "contract-addresses.json"), "utf8")
    );

    const [, buyer] = await ethers.getSigners();

    const registry = await ethers.getContractAt("GDMRegistry", addresses.GDMREGISTRY_ADDRESS, buyer);

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