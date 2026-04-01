// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./SGDNFT.sol";

contract GDMRegistry is Ownable, ReentrancyGuard {
    SGDNFT public immutable sgdNft;
    address public registrar;

    uint256 private _nextTokenId = 1;

    struct RegisterInput {
        address initialOwner;
        string sgdId;
        string rgdId;
        string cid;
        string accessCondition;
        uint256 price;
        uint256 collectionDate;
        string sampleType;
        string patientRef;
        string consentCode;
        string sampleHash;
        string encryptionScheme;
        string sequencingInfo;
        string signatureRef;
        string encHash;
        string tokenURI;
    }

    struct SGDRecord {
        uint256 tokenId;
        string sgdId;
        string rgdId;
        string cid;
        address registeredOwner; // owner at initial registration
        string accessCondition;
        uint256 price;
        uint256 collectionDate;
        string sampleType;
        string patientRef;
        string consentCode;
        string sampleHash;
        string encryptionScheme;
        string sequencingInfo;
        string signatureRef;
        string encHash;
        uint256 createdAt;
        bool active;
    }

    struct PublicRecord {
        uint256 tokenId;
        string sgdId;
        string rgdId;
        address currentOwner;
        string accessCondition;
        uint256 price;
        uint256 collectionDate;
        string sampleType;
        string patientRef;
        string consentCode;
        string sampleHash;
        string encryptionScheme;
        string sequencingInfo;
        bool active;
    }

    mapping(uint256 => SGDRecord) private _records; // save all records by tokenId
    mapping(uint256 => mapping(address => bool)) public hasPurchased; // each token, addressed purchased full access = true

    event RegistrarUpdated(address indexed newRegistrar);
    event SGDRegistered(
        uint256 indexed tokenId,
        address indexed initialOwner,
        string sgdId,
        string cid,
        uint256 price
    );
    event FullAccessPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 amount
    );
    event AccessConditionUpdated(uint256 indexed tokenId, string newCondition);
    event PriceUpdated(uint256 indexed tokenId, uint256 newPrice);
    event CIDUpdated(uint256 indexed tokenId, string newCid);
    event SGDDeactivated(uint256 indexed tokenId);

    error NotRegistrar();
    error ZeroAddress();
    error RecordNotFound();
    error InactiveRecord();
    error AlreadyPurchased();
    error WrongPayment();
    error Unauthorized();
    error PaymentFailed();

    constructor(address nftAddress, address initialOwner)
        Ownable(initialOwner)
    {
        if (nftAddress == address(0)) revert ZeroAddress();
        sgdNft = SGDNFT(nftAddress);
        registrar = initialOwner;
    }

    modifier onlyRegistrar() {
        if (msg.sender != registrar) revert NotRegistrar();
        _;
    }

    modifier recordExists(uint256 tokenId) {
        if (_records[tokenId].tokenId == 0) revert RecordNotFound();
        _;
    }

    function setRegistrar(address newRegistrar) external onlyOwner {
        if (newRegistrar == address(0)) revert ZeroAddress();
        registrar = newRegistrar;
        emit RegistrarUpdated(newRegistrar);
    }

    // function central of contract
    function registerSGD(
        RegisterInput calldata input
    ) external onlyRegistrar returns (uint256 tokenId) {
        if (input.initialOwner == address(0)) revert ZeroAddress();

        tokenId = _nextTokenId;
        _nextTokenId++;

        _records[tokenId] = SGDRecord({
            tokenId: tokenId,
            sgdId: input.sgdId,
            rgdId: input.rgdId,
            cid: input.cid,
            registeredOwner: input.initialOwner,
            accessCondition: input.accessCondition,
            price: input.price,
            collectionDate: input.collectionDate,
            sampleType: input.sampleType,
            patientRef: input.patientRef,
            consentCode: input.consentCode,
            sampleHash: input.sampleHash,
            encryptionScheme: input.encryptionScheme,
            sequencingInfo: input.sequencingInfo,
            signatureRef: input.signatureRef,
            encHash: input.encHash,
            createdAt: block.timestamp,
            active: true
        });

        if (bytes(input.tokenURI).length > 0) {
            sgdNft.mintWithURI(input.initialOwner, tokenId, input.tokenURI);
        } else {
            sgdNft.mint(input.initialOwner, tokenId);
        }

        emit SGDRegistered(
            tokenId,
            input.initialOwner,
            input.sgdId,
            input.cid,
            input.price
        );
    }

    // return PublicRecord
    function getPublicRecord(
        uint256 tokenId
    ) external view recordExists(tokenId) returns (PublicRecord memory) {
        SGDRecord storage r = _records[tokenId];

        return PublicRecord({
            tokenId: r.tokenId,
            sgdId: r.sgdId,
            rgdId: r.rgdId,
            currentOwner: sgdNft.ownerOf(tokenId),
            accessCondition: r.accessCondition,
            price: r.price,
            collectionDate: r.collectionDate,
            sampleType: r.sampleType,
            patientRef: r.patientRef,
            consentCode: r.consentCode,
            sampleHash: r.sampleHash,
            encryptionScheme: r.encryptionScheme,
            sequencingInfo: r.sequencingInfo,
            active: r.active
        });
    }

    // retutn full SGDRecord 
    function getFullRecord(
        uint256 tokenId
    ) external view recordExists(tokenId) returns (SGDRecord memory) {
        return _records[tokenId];
    }

    function getCID(
        uint256 tokenId
    ) external view recordExists(tokenId) returns (string memory) {
        address currentOwner = sgdNft.ownerOf(tokenId);

        if (
            msg.sender != currentOwner &&
            msg.sender != registrar &&
            msg.sender != owner() &&
            !hasPurchased[tokenId][msg.sender]
        ) {
            revert Unauthorized();
        }

        return _records[tokenId].cid;
    }

    // logic for purchasing full access 
    function purchaseFullAccess(
        uint256 tokenId
    ) external payable nonReentrant recordExists(tokenId) {
        SGDRecord storage r = _records[tokenId];

        if (!r.active) revert InactiveRecord();
        if (hasPurchased[tokenId][msg.sender]) revert AlreadyPurchased();
        if (msg.value != r.price) revert WrongPayment();

        hasPurchased[tokenId][msg.sender] = true;

        address seller = sgdNft.ownerOf(tokenId);
        (bool ok, ) = payable(seller).call{value: msg.value}("");
        if (!ok) revert PaymentFailed();

        emit FullAccessPurchased(tokenId, msg.sender, msg.value);
    }

    // allows updating access conditions 
    function setAccessCondition(
        uint256 tokenId,
        string calldata newCondition
    ) external recordExists(tokenId) {
        _onlyTokenOwnerOrRegistrar(tokenId);
        _records[tokenId].accessCondition = newCondition;
        emit AccessConditionUpdated(tokenId, newCondition);
    }

    // allow full access to price change
    function setPrice(
        uint256 tokenId,
        uint256 newPrice
    ) external recordExists(tokenId) {
        _onlyTokenOwnerOrRegistrar(tokenId);
        _records[tokenId].price = newPrice;
        emit PriceUpdated(tokenId, newPrice);
    }

    // only registrar can change CID 
    function updateCID(
        uint256 tokenId,
        string calldata newCid
    ) external onlyRegistrar recordExists(tokenId) {
        _records[tokenId].cid = newCid;
        emit CIDUpdated(tokenId, newCid);
    }

    // allow owner/registrar to disable records.
    function deactivateSGD(
        uint256 tokenId
    ) external recordExists(tokenId) {
        _onlyTokenOwnerOrRegistrar(tokenId);
        _records[tokenId].active = false;
        emit SGDDeactivated(tokenId);
    }  

    //reurn next tokenId
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // 
    function _onlyTokenOwnerOrRegistrar(uint256 tokenId) internal view {
        address currentOwner = sgdNft.ownerOf(tokenId);
        if (
            msg.sender != currentOwner &&
            msg.sender != registrar &&
            msg.sender != owner()
        ) {
            revert Unauthorized();
        }
    }

    function tacoCanDecrypt(
        uint256 tokenId,
        address user
    ) external view recordExists(tokenId) returns (uint256) {
        if (!_records[tokenId].active) {
            return 0;
        }
        
        return hasPurchased[tokenId][user] ? 1 : 0;
    }
}