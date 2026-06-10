import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("RGDNFT Contract Unit Tests", function () {
  async function deployRGDFixture() {
    const [owner, sc, user1, user2] = await ethers.getSigners();

    const RGDNFT = await ethers.getContractFactory("RGDNFT");
    const rgdNft = await RGDNFT.deploy(owner.address);

    // Grant SC permissions to the SC account.
    await rgdNft.authorizeSC(sc.address, true);

    // Add the decoy hash code to the whitelist.
    const codeHash = ethers.keccak256(ethers.toUtf8Bytes("secret_code_1"));
    await rgdNft.addSecretCodes([codeHash]);

    return { rgdNft, owner, sc, user1, user2 };
  }

  it("Should allow an authorized SC to mint RGD NFT with a valid code", async function () {
    const { rgdNft, sc, user1 } = await loadFixture(deployRGDFixture);
    const dataHash = ethers.keccak256(ethers.toUtf8Bytes("dna_raw_data"));

    await expect(rgdNft.connect(sc).mintRGD(user1.address, "secret_code_1", "ipfs://rgd_raw", dataHash))
      .to.emit(rgdNft, "RGDTokenMinted")
      .withArgs(user1.address, 1, "ipfs://rgd_raw");

    expect(await rgdNft.ownerOf(1)).to.equal(user1.address);
  });

  it("Should block unauthorized accounts from minting RGD", async function () {
    const { rgdNft, user2, user1 } = await loadFixture(deployRGDFixture);
    const dataHash = ethers.keccak256(ethers.toUtf8Bytes("dna_raw_data"));

    await expect(
      rgdNft.connect(user2).mintRGD(user1.address, "secret_code_1", "ipfs://rgd_raw", dataHash)
    ).to.be.revertedWith("Caller is not an authorized Sequencing Center");
  });

  it("[Novelty 1] Should strictly revert if the same One-Time Code is reused", async function () {
    const { rgdNft, sc, user1, user2 } = await loadFixture(deployRGDFixture);
    const dataHash = ethers.keccak256(ethers.toUtf8Bytes("dna_raw_data"));

    // Successfully
    await rgdNft.connect(sc).mintRGD(user1.address, "secret_code_1", "ipfs://rgd_1", dataHash);

    // Attempt to reuse the same code "secret_code_1" -> Should be reverted
    await expect(
      rgdNft.connect(sc).mintRGD(user2.address, "secret_code_1", "ipfs://rgd_2", dataHash)
    ).to.be.revertedWith("Error: This code has already been used for registration");
  });
});