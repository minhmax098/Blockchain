// represent the ownership layer
// each registered genomic data is mapped to 1 NFT
// NFT owner is as the current owner of dataset
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SGDNFT is ERC721, Ownable {
    address public minter;

    mapping(uint256 => string) private _tokenURIs;

    event MinterUpdated(address indexed newMinter);
    event TokenMinted(address indexed to, uint256 indexed tokenId, string tokenURI);

    error NotMinter();
    error ZeroAddress();
    error TokenNotMinted();

    constructor(address initialOwner)
        ERC721("SecureGenomicData", "SGD")
        Ownable(initialOwner)
    {}

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert ZeroAddress();
        minter = newMinter;
        emit MinterUpdated(newMinter);
    }

    function mint(address to, uint256 tokenId) external onlyMinter {
        _safeMint(to, tokenId);
        emit TokenMinted(to, tokenId, "");
    }

    function mintWithURI(
        address to,
        uint256 tokenId,
        string calldata tokenURI_
    ) external onlyMinter {
        _safeMint(to, tokenId);
        _tokenURIs[tokenId] = tokenURI_;
        emit TokenMinted(to, tokenId, tokenURI_);
    }

    function setTokenURI(
        uint256 tokenId,
        string calldata tokenURI_
    ) external onlyMinter {
        if (_ownerOf(tokenId) == address(0)) revert TokenNotMinted();
        _tokenURIs[tokenId] = tokenURI_;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenNotMinted();
        return _tokenURIs[tokenId];
    }
}