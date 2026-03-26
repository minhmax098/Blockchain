import { network } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    const { ethers } = await network.connect();
    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const sgdNFT = await ethers.deployContract("SGDNFT", [deployer.address]);
    await sgdNFT.waitForDeployment();
    const sgdNFTAddress = await sgdNFT.getAddress();

    console.log("SGDNFT deployed to:", sgdNFTAddress);

    const registry = await ethers.deployContract("GDMRegistry", [
        sgdNFTAddress,
        deployer.address,
    ]);
    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();

    console.log("GDMRegistry deployed to:", registryAddress);

    const tx = await sgdNFT.setMinter(registryAddress);
    await tx.wait();

    console.log("Minter set to registry:", registryAddress);

    const out = {
        network: (await ethers.provider.getNetwork()).chainId.toString(),
        SGDNFT_ADDRESS: sgdNFTAddress,
        GDMREGISTRY_ADDRESS: registryAddress,
    };

    const outPath = path.resolve(
        process.cwd(),
        "../server/src/config/contract-addresses.json"
    );
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
    console.log("Contract addresses saved to:", outPath);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});