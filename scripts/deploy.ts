import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
    // const { ethers } = await network.connect();
    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    // 1. Deploy SGDNFT
    const sgdNFT = await ethers.deployContract("SGDNFT", [deployer.address]);
    await sgdNFT.waitForDeployment();
    const sgdNFTAddress = await sgdNFT.getAddress();
    console.log("SGDNFT deployed to:", sgdNFTAddress);

    // 2. Deploy RGDNFT
    const rgdNFT = await ethers.deployContract("RGDNFT", [deployer.address]);
    await rgdNFT.waitForDeployment();
    const rgdNFTAddress = await rgdNFT.getAddress();
    console.log("RGDNFT deployed to:", rgdNFTAddress);

    // 3. Deploy GDMRegistry 
    const registry = await ethers.deployContract("GDMRegistry", [
        sgdNFTAddress,
        deployer.address,
    ]);
    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();
    console.log("GDMRegistry deployed to:", registryAddress);

    // Configure Registry setting for RGDNFT (implement listRGDNFT)
    await (await rgdNFT.setGDMRegistry(registryAddress)).wait();
    console.log("RGDNFT linked to Registry:");

    // Grant Minter permissions to the Reistry at SGDNFT
    await (await sgdNFT.setMinter(registryAddress)).wait();
    console.log("Minter set to registry: ", registryAddress);

    // Granting Deployers permision to act as "authorized SC" for demo
    await (await rgdNFT.authorizeSC(deployer.address, true)).wait();
    console.log("Deployer authorized as SC for RGDNFT: ");
    
    // const tx = await sgdNFT.setMinter(registryAddress);
    // await tx.wait();
    // console.log("Minter set to registry:", registryAddress);

    const out = {
        network: (await ethers.provider.getNetwork()).chainId.toString(),
        SGDNFT_ADDRESS: sgdNFTAddress,
        RGDNFT_ADDRESS: rgdNFTAddress,
        GDMREGISTRY_ADDRESS: registryAddress,
    };

    const outPath = path.join(__dirname, "..", "backend", "contract-addresses.json");
    fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});