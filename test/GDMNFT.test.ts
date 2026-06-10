import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("GDMRegistry System Comprehensive Tests", function () {
  async function deployFixture() {
    const [owner, minter, registrar, user1, user2] = await ethers.getSigners();

    // 1. Deploy SGDNFT Layer
    const SGDNFT = await ethers.getContractFactory("SGDNFT");
    const sgdNft = await SGDNFT.deploy(owner.address);

    // 2. Deploy GDMRegistry Contract
    const GDMRegistry = await ethers.getContractFactory("GDMRegistry");
    const registry = await GDMRegistry.deploy(await sgdNft.getAddress(), owner.address);

    // 3. Deploy RGDNFT Contract
    const RGDNFT = await ethers.getContractFactory("RGDNFT");
    const rgdNft = await RGDNFT.deploy(owner.address);

    // 4. Establish system permission links (Cross-linking Configuration)
    await sgdNft.setMinter(await registry.getAddress());
    await rgdNft.setGDMRegistry(await registry.getAddress());
    await rgdNft.authorizeSC(owner.address, true);

    // Load the whitelist code to test the raw data casting flow.
    const codeHash = ethers.keccak256(ethers.toUtf8Bytes("secret1"));
    await rgdNft.addSecretCodes([codeHash]);

    return { sgdNft, registry, rgdNft, owner, minter, registrar, user1, user2 };
  }

  describe("Function: registerSGD", function () {
    it("should register a new SGD successfully and trigger lineage checks", async function () {
      const { registry, sgdNft, rgdNft, user1 } = await loadFixture(deployFixture);

      // Mint RGD NFT raw for patient (user1)
      await rgdNft.mintRGD(user1.address, "secret1", "ipfs://rgd", ethers.keccak256(ethers.toUtf8Bytes("data")));
      
      // Send a list command directly, activate the onERC721Received callback to automatically record the original owner.
      await rgdNft.connect(user1).listRGDNFT(1);

      const price = ethers.parseEther("0.1");
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdTokenId: 1, // on-chain Parent Token ID
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: ethers.zeroPadValue("0x1234", 32),
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: ethers.zeroPadValue("0x5678", 32),
        tokenURI: "ipfs://testURI"
      };

      await expect(registry.registerSGD(input))
        .to.emit(registry, "LatestVersionUpdated")
        .withArgs("SGD001", 1)
        .and.to.emit(registry, "SGDRegistered")
        .withArgs(1, user1.address, "SGD001", "QmTestCID", price);

      const record = await registry.getFullRecord(1);
      expect(record.sgdId).to.equal("SGD001");
      expect(record.rgdTokenId).to.equal(1n);
      expect(record.registeredOwner).to.equal(user1.address);
      expect(record.active).to.be.true;
      expect(record.version).to.equal(0);

      // Check the minting status and URI of the SGD NFT asset
      expect(await sgdNft.ownerOf(1)).to.equal(user1.address);
      expect(await sgdNft.tokenURI(1)).to.equal("ipfs://testURI");
    });

    it("should prevent duplicate sgdId registration", async function () {
      const { registry, rgdNft, user1 } = await loadFixture(deployFixture);

      await rgdNft.mintRGD(user1.address, "secret1", "ipfs://rgd", ethers.keccak256(ethers.toUtf8Bytes("data")));
      await rgdNft.connect(user1).listRGDNFT(1);

      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdTokenId: 1,
        cid: "QmTestCID",
        accessCondition: "Public",
        price: ethers.parseEther("0.1"),
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: ethers.zeroPadValue("0x1234", 32),
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: ethers.zeroPadValue("0x5678", 32),
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);
      await expect(registry.registerSGD(input)).to.be.revertedWithCustomError(registry, "SGDAlreadyRegistered");
    });
  });

  describe("Function: purchaseFullAccess", function () {
    it("should allow a user to purchase full access and accurately execute 2.5% marketplace fee split", async function () {
      const { registry, sgdNft, rgdNft, owner, user1, user2 } = await loadFixture(deployFixture);

      await rgdNft.mintRGD(user1.address, "secret1", "ipfs://rgd", ethers.keccak256(ethers.toUtf8Bytes("data")));
      await rgdNft.connect(user1).listRGDNFT(1);

      const price = ethers.parseEther("1.0"); // Use the constant 1 ETH to easily calculate cash flow
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdTokenId: 1,
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: ethers.zeroPadValue("0x1234", 32),
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: ethers.zeroPadValue("0x5678", 32),
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);

      // Measure the balances of the wallets before proceeding with the data purchase
      const sellerBalanceBefore = await ethers.provider.getBalance(user1.address);
      const feeReceiverBalanceBefore = await ethers.provider.getBalance(owner.address); // Default feeReceiver is the owner

      await expect(registry.connect(user2).purchaseFullAccess(1, { value: price }))
        .to.emit(registry, "FullAccessPurchased")
        .withArgs(1, user2.address, price);

      // Measure the balances of the wallets after the settlement transaction
      const sellerBalanceAfter = await ethers.provider.getBalance(user1.address);
      const feeReceiverBalanceAfter = await ethers.provider.getBalance(owner.address);

      // Calculate the cash flow split according to the 2.5% - 97.5% model
      const expectedPlatformFee = (price * 250n) / 10000n; // 2.5% Platform Fee
      const expectedSellerPayout = price - expectedPlatformFee; // 97.5% Seller Payout

      // Assert the on-chain fund distribution is accurate
      expect(sellerBalanceAfter - sellerBalanceBefore).to.equal(expectedSellerPayout);
      expect(feeReceiverBalanceAfter - feeReceiverBalanceBefore).to.equal(expectedPlatformFee);

      // Verify the infrastructure access rights
      expect(await registry.canReleaseKey(1, user2.address)).to.be.true;
      const cid = await registry.connect(user2).getCID(1);
      expect(cid).to.equal("QmTestCID");
    });

    it("should prevent double purchases from the same buyer address", async function () {
      const { registry, rgdNft, user1, user2 } = await loadFixture(deployFixture);

      await rgdNft.mintRGD(user1.address, "secret1", "ipfs://rgd", ethers.keccak256(ethers.toUtf8Bytes("data")));
      await rgdNft.connect(user1).listRGDNFT(1);

      const price = ethers.parseEther("0.1");
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdTokenId: 1,
        cid: "QmTestCID",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: ethers.zeroPadValue("0x1234", 32),
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: ethers.zeroPadValue("0x5678", 32),
        tokenURI: "ipfs://testURI"
      };

      await registry.registerSGD(input);
      await registry.connect(user2).purchaseFullAccess(1, { value: price });

      await expect(registry.connect(user2).purchaseFullAccess(1, { value: price }))
        .to.be.revertedWithCustomError(registry, "AlreadyPurchased");
    });
  });

  describe("Function: updateSGDVersion (Address Rotation)", function () {
    it("should correctly update version parameters, archive history, and migrate ownership to rotated wallet", async function () {
      const { registry, sgdNft, rgdNft, user1, user2 } = await loadFixture(deployFixture);

      await rgdNft.mintRGD(user1.address, "secret1", "ipfs://rgd", ethers.keccak256(ethers.toUtf8Bytes("data")));
      await rgdNft.connect(user1).listRGDNFT(1);

      const price = ethers.parseEther("0.1");
      const input = {
        initialOwner: user1.address,
        sgdId: "SGD001",
        rgdTokenId: 1,
        cid: "QmTestCID_v0",
        accessCondition: "Public",
        price: price,
        collectionDate: 1234567890,
        sampleType: "Blood",
        patientRef: "P001",
        consentCode: "C001",
        sampleHash: ethers.zeroPadValue("0x1234", 32),
        encryptionScheme: "AES",
        sequencingInfo: "SeqInfo",
        signatureRef: "SigRef",
        encHash: ethers.zeroPadValue("0x5678", 32),
        tokenURI: "ipfs://testURI_v0"
      };

      await registry.registerSGD(input);

      // Execute Address Rotation: Update information and move the NFT to the new receiving wallet (user2).
      const newPrice = ethers.parseEther("0.2");
      await expect(registry.updateSGDVersion(
        1,
        "QmTestCID_v1",
        "Private",
        newPrice,
        "ipfs://testURI_v1",
        user2.address // New wallet receiving the economic benefits
      ))
      .to.emit(registry, "SGDVersionUpdated")
      .withArgs(1, "SGD001", "Private", newPrice, 1, user2.address);

      // Check the current record reflects the correct state of the new wallet
      const record = await registry.getFullRecord(1);
      expect(record.cid).to.equal("QmTestCID_v1");
      expect(record.accessCondition).to.equal("Private");
      expect(record.price).to.equal(newPrice);
      expect(record.version).to.equal(1);
      expect(record.registeredOwner).to.equal(user2.address);

      // Points: Verify that the NFT ERC-721 has successfully transferred ownership on-chain
      expect(await sgdNft.ownerOf(1)).to.equal(user2.address);
      expect(await sgdNft.tokenURI(1)).to.equal("ipfs://testURI_v1");

      // Points: Verify the immutability of the version history array (History tracking)
      const versions = await registry.getVersionsOfSgd(1);
      expect(versions.length).to.equal(1);
      expect(versions[0].cid).to.equal("QmTestCID_v0");
      expect(versions[0].version).to.equal(0);
      expect(versions[0].registeredOwner).to.equal(user1.address); // Version 0 record still stores the old wallet for auditing purposes
    });
  });
});
