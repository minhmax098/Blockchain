import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

dotenv.config();

const addressesPath = path.join(__dirname, "contract-addresses.json");
const addresses = JSON.parse(fs.readFileSync(addressesPath, "utf-8"));

const registryArtifact = require("../artifacts/contracts/GDMRegistry.sol/GDMRegistry.json");

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);

export const registry = new ethers.Contract(
    addresses.GDMREGISTRY_ADDRESS,
    registryArtifact.abi,
    provider
);

export async function hasPurchased(tokenId: number, buyer: string): Promise<boolean> {
    return await registry.hasPurchased(tokenId, buyer);
}

export async function getPublicRecord(tokenId: number) {
    return await registry.getPublicRecord(tokenId);
}

export async function nextTokenId(): Promise<bigint> {
    return await registry.nextTokenId();
}