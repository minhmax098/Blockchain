import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("GDMNFT", function () {
  async function deployFixture() {
    const [owner, minter, registrar, user1, user2] = await ethers.getSigners();

    // Deploy SGDNFT
    const SGDNFT = await ethers.getContractFactory("SGDNFT");
    const sgdNft = await SGDNFT.deploy(owner.address);

    // Deploy GDMRegistry
    const GDMRegistry = await ethers.getContractFactory("GDMRegistry");
    const registry = await GDMRegistry.deploy(await sgdNft.getAddress(), owner.address);

    // Set minter in SGDNFT to be the GDMRegistry
    await sgdNft.setMinter(await registry.getAddress());

    return { sgdNft, registry, owner, minter, registrar, user1, user2 };
  }

  describe("registerSGD", function () {
    it("should register a new SGD successfully", async function () {
      const { registry, sgdNft, owner, user1 } = await loadFixture(deployFixture);

      const price = ethers.parseEther("0.1");

      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await expect(registry.registerSGD(input))
        .to.emit(registry, "LatestVersionUpdated")
        .withArgs("SGD001", 1)
        .and.to.emit(registry, "SGDRegistered")
        .withArgs(1, user1.address, "SGD001", "QmTestCID", price);

      const record = await registry.getFullRecord(1);
      expect(record.sgdId).to.equal("SGD001");
      expect(record.cid).to.equal("QmTestCID");
      expect(record.registeredOwner).to.equal(user1.address);
      expect(record.active).to.be.true;
      expect(record.version).to.equal(0);

      // check if NFT was minted properly
      expect(await sgdNft.ownerOf(1)).to.equal(user1.address);
      expect(await sgdNft.tokenURI(1)).to.equal("ipfs://testURI");
    });

    it("should prevent duplicate sgdId registration", async function () {
      const { registry, user1 } = await loadFixture(deployFixture);

      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: ethers.parseEther("0.1"),
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);
      await expect(registry.registerSGD(input)).to.be.revertedWithCustomError(registry, "SGDAlreadyRegistered");
    });
  });

  describe("purchaseFullAccess", function () {
    it("should allow a user to purchase full access", async function () {
      const { registry, sgdNft, owner, user1, user2 } = await loadFixture(deployFixture);

      const price = ethers.parseEther("0.1");

      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);

      // Check balance before
      const sellerBalanceBefore = await ethers.provider.getBalance(user1.address);

      await expect(registry.connect(user2).purchaseFullAccess(1, { value: price }))
        .to.emit(registry, "FullAccessPurchased")
        .withArgs(1, user2.address, price);

      // Check balance after
      const sellerBalanceAfter = await ethers.provider.getBalance(user1.address);
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(price);

      // Verify access
      expect(await registry.canReleaseKey(1, user2.address)).to.be.true;

      // Should be able to get CID
      const cid = await registry.connect(user2).getCID(1);
      expect(cid).to.equal("QmTestCID");
    });

    it("should prevent double purchases", async function () {
      const { registry, user1, user2 } = await loadFixture(deployFixture);

      const price = ethers.parseEther("0.1");
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);

      await registry.connect(user2).purchaseFullAccess(1, { value: price });

      await expect(registry.connect(user2).purchaseFullAccess(1, { value: price }))
        .to.be.revertedWithCustomError(registry, "AlreadyPurchased");
    });

    it("should revert on wrong payment amount", async function () {
      const { registry, user1, user2 } = await loadFixture(deployFixture);

      const price = ethers.parseEther("0.1");
      const wrongPrice = ethers.parseEther("0.05");
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);

      await expect(registry.connect(user2).purchaseFullAccess(1, { value: wrongPrice }))
        .to.be.revertedWithCustomError(registry, "WrongPayment");
    });
  });

  describe("updateSGDVersion", function () {
    it("should correctly update the version, save history, and update URI", async function () {
      const { registry, sgdNft, owner, user1 } = await loadFixture(deployFixture);

      const price = ethers.parseEther("0.1");
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID_v0",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI_v0"
      };

      await registry.registerSGD(input);

      const newPrice = ethers.parseEther("0.2");
      await expect(registry.updateSGDVersion(
        1,
        "QmTestCID_v1",
        "Private",
        newPrice,
        "ipfs://testURI_v1"
      ))
      .to.emit(registry, "SGDVersionUpdated")
      .withArgs(1, "SGD001", "Private", newPrice, 1);

      // Check current record
      const record = await registry.getFullRecord(1);
      expect(record.cid).to.equal("QmTestCID_v1");
      expect(record.accessCondition).to.equal("Private");
      expect(record.price).to.equal(newPrice);
      expect(record.version).to.equal(1);

      // Check NFT URI
      expect(await sgdNft.tokenURI(1)).to.equal("ipfs://testURI_v1");

      // Check version history
      const versions = await registry.getVersionsOfSgd(1);
      expect(versions.length).to.equal(1);
      expect(versions[0].cid).to.equal("QmTestCID_v0");
      expect(versions[0].version).to.equal(0);
      expect(versions[0].price).to.equal(price);
    });
  });

  describe("deactivateSGD & isLatestVersion", function () {
    it("should deactivate an active SGD", async function () {
      const { registry, user1 } = await loadFixture(deployFixture);

      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: ethers.parseEther("0.1"),
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);

      await expect(registry.deactivateSGD(1))
        .to.emit(registry, "SGDDeactivated")
        .withArgs(1);

      const record = await registry.getFullRecord(1);
      expect(record.active).to.be.false;
    });

    it("should return true for isLatestVersion", async function () {
      const { registry, user1 } = await loadFixture(deployFixture);

      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdId: "RGD001",
        cid: "QmTestCID",
        accessCondition: "Public",
        price: ethers.parseEther("0.1"),
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: "0xHash",
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: "EncHash",
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);

      expect(await registry.isLatestVersion(1)).to.be.true;
    });
  });
});
