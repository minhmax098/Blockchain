// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Represent raw, unsequenced genomic data 
// Parent NFT in composable NFT model
// Algorithm 1: RGD NFT Minting, Approve and Listing

contract RGDNFT is ERC721URIStorage, Ownable {
    uint256 private _tokenCount;
    uint256 private itemCount;
    // address of the registry contract 
    address public gdmRegistry;

    // whitelist: store hash of secret code (noone knows original code on the string)
    mapping(bytes32 => bool) public codeWhiteList;
    // check code has already been used (data duplication prevention)
    mapping(bytes32 => bool) public codeUses;

    event RGDTokenMinted(address indexed owner, uint256 indexed tokenId, string tokenURI);
    event RGDTokenApproval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event RGDTokenListed(uint256 indexed tokenId, address indexed owner);
    event SecretCodeAdded(uint256 count);

    constructor(address initialOwner) ERC721("RawGenomicData", "RGD") Ownable(initialOwner) {}

    // function for admin to load a list of secret code (in hash format)
    function addSecretCodes(bytes32[] calldata hashedCodes) external onlyOwner {
        for (uint i = 0; i < hashedCodes.length; i++) {
            require(!codeWhiteList[hashedCodes[i]], "Code hash already exists in whitelist");
            codeWhiteList[hashedCodes[i]] = true;
        }
        emit SecretCodeAdded(hashedCodes.length);
    }

    function setGDMRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "Invalid registry address");
        gdmRegistry = _registry;
    }

    // mintRGD: request Secret Code to authenticate data origin from Hospital
    // to: NFT receiving address (Owner)
    // secretCode: plaintext secret code that Owner received from Admin
    // uri CID of encrypted RGD file on IPFS (Ek1(RGD))
    function mintRGD(address to, string memory secretCode, string memory uri) external returns (uint256) {
        // Create hash from input secret code
        bytes32 codeHash = keccak256(abi.encodePacked(secretCode));

        // 1. Check if the code is in the Admin whitelist
        require(codeWhiteList[codeHash], "Error: Invalid Secret Code");

        // 2. Check if the code has already been used (One-time use mechanism)
        require(!codeUses[codeHash], "Error: This code has already been used for registration");

        // Mark the code as used (prevent reuse, not duplicate data)
        codeUses[codeHash] = true;

        _tokenCount++; // increase tokenCount 
        uint256 tokenId = _tokenCount; // assign tokenId

        // Mint the NFT and set token URI
        _safeMint(to, tokenId); // Mint NFT and assign owner is caller
        _setTokenURI(tokenId, uri); // tokenURI

        emit RGDTokenMinted(to, tokenId, uri);
        return tokenId;
    }

    // Allow NFT owner to grant permission to the GDM to use their NFT
    function approveRegistry(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner, "Caller is not the token owner");

        // Approve address of GDMSCAddress use NFT 
        _approve(gdmRegistry, tokenId, owner); // Approve the registry to manage the token
        emit RGDTokenApproval(owner, gdmRegistry, tokenId);
    }

    // List the NFT to the GDM system by transferring ownership to the NFT to the GDM contract address
    function listRGDNFT(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not owner nor approved");
        itemCount++; // increase itemCount
        // Transfer NFT to address of contract GDM
        _transfer(msg.sender, gdmRegistry, tokenId);

        emit RGDTokenListed(tokenId, msg.sender);
    }

    // check valid or invalid of token
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
