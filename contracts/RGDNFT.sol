// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Represent raw, unsequenced genomic data 
// Parent NFT in composable NFT model
// Algorithm 1: RGD NFT Minting, Approve and Listing

contract RGDNFT is ERC721URIStorage, Ownable {
    uint256 private _nextTokenId;

    // address of the registry contract 
    address public gdmRegistry;

    event RGDTokenMinted(address indexed owner, uint256 indexed tokenId, string tokenURI);

    constructor(address initialOwner) ERC721("RawGenomicData", "RGD") Ownable(initialOwner) {}

    modifier onlyRegistry() {
        require(msg.sender == gdmRegistry, "Caller is not the registry");
        _;
    }

    function setGDMRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "Invalid registry address");
        gdmRegistry = _registry;
    }

    // User mints the NFT for their raw template
    // template owner's wallet address
    // uri Metadata contains basic info, the hash of the raw template
    function mintRGD(address to, string memory uri) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit RGDTokenMinted(to, tokenId, uri);
        return tokenId;
    }

    // check valid or invalid of token
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
