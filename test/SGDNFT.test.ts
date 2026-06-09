import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("SGDNFT Contract Unit Tests", function () {
  async function deploySGDFixture() {
    const [owner, fakeRegistry, user1, user2] = await ethers.getSigners();

    const SGDNFT = await ethers.getContractFactory("SGDNFT");
    const sgdNft = await SGDNFT.deploy(owner.address);

    // Thiết lập một địa chỉ giả lập làm Registry (Minter)
    await sgdNft.setMinter(fakeRegistry.address);

    return { sgdNft, owner, fakeRegistry, user1, user2 };
  }

  it("Should allow the authorized Minter (Registry) to mint SGD NFT", async function () {
    const { sgdNft, fakeRegistry, user1 } = await loadFixture(deploySGDFixture);

    await expect(sgdNft.connect(fakeRegistry).mintWithURI(user1.address, 1, "ipfs://sgd_uri"))
      .to.emit(sgdNft, "TokenMinted")
      .withArgs(user1.address, 1, "ipfs://sgd_uri");

    expect(await sgdNft.ownerOf(1)).to.equal(user1.address);
  });

  it("Should block non-minter accounts from directly minting assets", async function () {
    const { sgdNft, user1 } = await loadFixture(deploySGDFixture);

    await expect(
      sgdNft.connect(user1).mint(user1.address, 100)
    ).to.be.revertedWithCustomError(sgdNft, "NotMinter");
  });

  it("Should allow Minter to execute transferByMinter for Address Rotation", async function () {
    const { sgdNft, fakeRegistry, user1, user2 } = await loadFixture(deploySGDFixture);

    // Mint token 1 cho user1
    await sgdNft.connect(fakeRegistry).mint(user1.address, 1);

    // Giả lập Registry gọi hàm dịch chuyển quyền sở hữu sang ví nhận tiền mới (user2)
    await sgdNft.connect(fakeRegistry).transferByMinter(user1.address, user2.address, 1);

    // Quyền sở hữu phải thay đổi on-chain
    expect(await sgdNft.ownerOf(1)).to.equal(user2.address);
  });
});