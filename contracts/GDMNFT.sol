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
        address registeredOwner;
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
        uint256 version;
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

    mapping(uint256 => SGDRecord) private _records;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;

    // _versionsOfSgd["SGD001"] = [1, 2, 3];
    // latestTokenBySgdId["SGD001"] = 3;
    // Means: The array stores the entire version history. The variable `latest` stores the currently active token.
    mapping (string => uint256[]) private _versionOfSgd;
    mapping (string => uint256) public latestTokenBySgdId;

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

    event SGDVersionCreated(
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId,
        string sgdId,
        string newAccessCondition,
        uint256 newPrice
    );

    error NotLatestVersion();
    error SGDAlreadyRegistered();

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

    // SC creates the first SGD NFT version and stores its access condition, price, CID, and owner information.
    function registerSGD(
        RegisterInput calldata input
    ) external onlyRegistrar returns (uint256 tokenId) {
        if (latestTokenBySgdId[input.sgdId] != 0) revert SGDAlreadyRegistered();

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
            active: true,
            version: 1
        });

        if (bytes(input.tokenURI).length > 0) {
            sgdNft.mintWithURI(input.initialOwner, tokenId, input.tokenURI);
        } else {
            sgdNft.mint(input.initialOwner, tokenId);
        }

        latestTokenBySgdId[input.sgdId] = tokenId;
        _versionOfSgd[input.sgdId].push(tokenId);

        emit SGDRegistered(
            tokenId,
            input.initialOwner,
            input.sgdId,
            input.cid,
            input.price
        );
    }

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

    // Buyer can use to pay, 
    // Buyers can only purchase the latest active version.
    function purchaseFullAccess(
        uint256 tokenId
    ) external payable nonReentrant recordExists(tokenId) {
        SGDRecord storage r = _records[tokenId];

        // 1. NFT version must be active 
        if (!r.active) revert InactiveRecord();

        // 2. Buyer can only purchase the latest SGD NFT version
        if (latestTokenBySgdId[r.sgdId] != tokenId) revert NotLatestVersion();

        // 3. Prevent repeated purchase by the same buyer
        if (hasPurchased[tokenId][msg.sender]) revert AlreadyPurchased();
        
        // 4. Buyer must pay the latest price
        if (msg.value != r.price) revert WrongPayment();

        hasPurchased[tokenId][msg.sender] = true;

        address seller = sgdNft.ownerOf(tokenId);
        (bool ok, ) = payable(seller).call{value: msg.value}("");
        if (!ok) revert PaymentFailed();

        emit FullAccessPurchased(tokenId, msg.sender, msg.value);
    }

    // use for SC/TACo check buyer receive key or not
    // SC/TACo check before release key.
    function canReleaseKey(
        uint256 tokenId, 
        address buyer
    ) external view recordExists(tokenId) returns (bool) {
        SGDRecord storage r = _records[tokenId];

        return (
            r.active &&
            latestTokenBySgdId[r.sgdId] == tokenId &&
            hasPurchased[tokenId][buyer]
        );
    }

    // use when data owner wants to update access condition or price.
    // Blockchain immutable, but system supports logical mutability through NFT versioning
    function createNewSGDVersion(
        uint256 oldTokenId, 
        string calldata newCid, 
        string calldata newAccessCondition,
        uint256 newPrice,
        string calldata newTokenURI
    ) external onlyRegistrar recordExists(oldTokenId) returns (uint256 newTokenId) {
        // Implementation for creating a new version of SGD record
        // This could involve copying the existing record, allowing updates, and linking to the previous version
        SGDRecord storage oldRecord = _records[oldTokenId];

        if (!oldRecord.active) revert InactiveRecord();
        if (latestTokenBySgdId[oldRecord.sgdId] != oldTokenId) revert NotLatestVersion();

        oldRecord.active = false; // Deactivate old version

        newTokenId = _nextTokenId;
        _nextTokenId++;

        _records[newTokenId] = SGDRecord({
            tokenId: newTokenId,
            sgdId: oldRecord.sgdId,
            rgdId: oldRecord.rgdId,
            cid: newCid,
            registeredOwner: oldRecord.registeredOwner,
            accessCondition: newAccessCondition,
            price: newPrice,
            collectionDate: oldRecord.collectionDate,
            sampleType: oldRecord.sampleType,
            patientRef: oldRecord.patientRef,
            consentCode: oldRecord.consentCode,
            sampleHash: oldRecord.sampleHash,
            encryptionScheme: oldRecord.encryptionScheme,
            sequencingInfo: oldRecord.sequencingInfo, 
            signatureRef: oldRecord.signatureRef,
            encHash: oldRecord.encHash,
            createdAt: block.timestamp,
            active: true,
            version: oldRecord.version + 1
        });

        latestTokenBySgdId[oldRecord.sgdId] = newTokenId;
        _versionOfSgd[oldRecord.sgdId].push(newTokenId);

        if (bytes(newTokenURI).length > 0) {
            sgdNft.mintWithURI(oldRecord.registeredOwner, newTokenId, newTokenURI);
        } else {
            sgdNft.mint(oldRecord.registeredOwner, newTokenId);
        }

        emit SGDDeactivated(oldTokenId);
        emit SGDVersionCreated(
            oldTokenId, 
            newTokenId, 
            oldRecord.sgdId, 
            newAccessCondition, 
            newPrice
        );
    }

    // Data Owner only request update
    // SC/Registrar can create new version or deactivate
    function deactivateSGD(
        uint256 tokenId
    ) external onlyRegistrar recordExists(tokenId) {
        _records[tokenId].active = false;
        emit SGDDeactivated(tokenId);
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

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

    // Returns the entire version history.
    function getVersionOfSgd(
        string calldata sgdId
    ) external view returns (uint256[] memory) {
        return _versionOfSgd[sgdId];
    }

    // Checks if the current token is the latest version.
    function isLatestVersion(
        uint256 tokenId
    ) external view returns (bool) {
        SGDRecord storage r = _records[tokenId];
        return latestTokenBySgdId[r.sgdId] == tokenId;
    }
}