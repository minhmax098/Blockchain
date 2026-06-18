// GDMNFT: manage SGD metadata, access condition, pricing, NFT versioning, payment, latest active policy
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./SGDNFT.sol";

contract GDMRegistry is Ownable, ReentrancyGuard, IERC721Receiver {
    SGDNFT public immutable sgdNft;
    address public registrar;

    uint256 private _nextTokenId = 1;

    // SC creates SGD NFT for the first time: CID, price, access condition, patient metadata, sequencing metadata, tokenURI
    struct RegisterInput {
        address initialOwner;
        string sgdId;
        uint256 rgdTokenId;
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

    // on-chain metadata record
    // save: SGD identity, CID, access condition, price, owner, sequencing metadata, version numberactive/latest state
    struct SGDRecord {
        uint256 tokenId;
        string sgdId;
        uint256 rgdTokenId;
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
        uint256 rgdTokenId;
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

    // _versionsOfSgd[tokenId] = [record_v0, record_v1, ...];
    // latestTokenBySgdId["SGD001"] = 1;
    // Means: The array stores the entire version history. The variable `latest` stores the currently active token.
    mapping (uint256 => SGDRecord[]) private _versionsOfSgd;
    mapping (string => uint256) public latestTokenBySgdId;

    // Track original owners of RGD NFTs when they are deposited
    mapping(uint256 => address) public rgdOriginalOwners;

    // Platform fee configuration
    uint256 public platformFeePercentage = 250; // 2.5% = 250 basis points (out of 10000)
    address public feeReceiver;

    event RegistrarUpdated(address indexed newRegistrar);
    event RGDReceived(address indexed operator, address indexed from, uint256 indexed tokenId, bytes data);
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
    event SGDDeactivated(uint256 indexed tokenId);

    event SGDVersionUpdated(
        uint256 indexed tokenId,
        string sgdId,
        string newAccessCondition,
        uint256 newPrice,
        uint256 newVersion,
        address newOwner
    );

    event LatestVersionUpdated(
        string indexed sgdId,
        uint256 indexed latestTokenId
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
        feeReceiver = initialOwner; // Default fee receiver is the owner
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

    function setFeeConfiguration(uint256 newFeePercentage, address newFeeReceiver) external onlyOwner {
        require(newFeePercentage <= 10000, "Fee percentage cannot exceed 100%");
        require(newFeeReceiver != address(0), "Fee receiver cannot be zero address");
        platformFeePercentage = newFeePercentage;
        feeReceiver = newFeeReceiver;
    }

    // SC creates the first SGD NFT version and stores its access condition, price, CID, and owner information.
    function registerSGD(
        RegisterInput calldata input
    ) external onlyRegistrar returns (uint256 tokenId) {
        if (latestTokenBySgdId[input.sgdId] != 0) revert SGDAlreadyRegistered();

        if (input.initialOwner == address(0)) revert ZeroAddress();

        // Ensure the RGD NFT is deposited and trackable
        require(rgdOriginalOwners[input.rgdTokenId] != address(0), "RGD NFT not deposited in registry");

        tokenId = _nextTokenId;
        _nextTokenId++;
        

        SGDRecord memory r = SGDRecord({
            tokenId: tokenId,
            sgdId: input.sgdId,
            rgdTokenId: input.rgdTokenId,
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
            version: 0
        });

        _records[tokenId] = r;

        if (bytes(input.tokenURI).length > 0) {
            sgdNft.mintWithURI(input.initialOwner, tokenId, input.tokenURI);
        } else {
            sgdNft.mint(input.initialOwner, tokenId);
        }

        latestTokenBySgdId[input.sgdId] = tokenId;

        emit LatestVersionUpdated(input.sgdId, tokenId);

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
            rgdTokenId: r.rgdTokenId,
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

    // Allow the Registry (minter) to transfer NFTs on behalf of the owner when updating to a new version.
    //function transferByMinter(
    //    address from,
    //    address to,
    //    uint256 tokenId
    //) external onlyMinter {
    //    if (_ownerOf(tokenId) == address(0)) revert TokenNotMinted();
    //    if (to == address(0)) revert ZeroAddress();
    //    _transfer(from, to, tokenId);
    //}

    // Buyer purchases access to the latest active SGD NFT version, 
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

        // Calculate platform fee and seller payout
        uint256 platformFee = (msg.value * platformFeePercentage) / 10000;
        uint256 sellerPayout = msg.value - platformFee;

        // Pay the platform fee receiver
        if (platformFee > 0) {
            (bool feeOk, ) = payable(feeReceiver).call{value: platformFee}("");
            if (!feeOk) revert PaymentFailed();
        }

        // Pay the seller
        (bool ok, ) = payable(seller).call{value: sellerPayout}("");
        if (!ok) revert PaymentFailed();

        emit FullAccessPurchased(tokenId, msg.sender, msg.value);
    }

    // TACo/SC validates buyer eligibility before releasing decryption key shares
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
    // When: access conditions change, price changes, CID changes
    // THEN: update the old NFT, push old data to version array
    function updateSGDVersion(
        uint256 tokenId,
        string calldata newCid, 
        string calldata newAccessCondition,
        uint256 newPrice,
        string calldata newTokenURI,
        address newOwner    // 1. Add new wallet parameters
    ) external onlyRegistrar recordExists(tokenId) {
        SGDRecord storage record = _records[tokenId];

        if (!record.active) revert InactiveRecord();
        if (latestTokenBySgdId[record.sgdId] != tokenId) revert NotLatestVersion();

        // Push old data to version history before updating
        _versionsOfSgd[tokenId].push(record);

        // Update the current record with new information
        record.cid = newCid;
        record.accessCondition = newAccessCondition;
        record.price = newPrice;
        record.version = record.version + 1;

        // 2. Logic for transferring NFTs to a new wallet.
        if (newOwner != address(0) && newOwner != record.registeredOwner) {
            sgdNft.transferByMinter(record.registeredOwner, newOwner, tokenId);
            record.registeredOwner = newOwner;
        }

        if (bytes(newTokenURI).length > 0) {
            sgdNft.setTokenURI(tokenId, newTokenURI);
        }

        emit SGDVersionUpdated(
            tokenId,
            record.sgdId,
            newAccessCondition, 
            newPrice,
            record.version,
            record.registeredOwner    // 3. Add new owner log
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

    // Returns the entire version history.
    function getVersionsOfSgd(
        uint256 tokenId
    ) external view returns (SGDRecord[] memory) {
        return _versionsOfSgd[tokenId];
    }

    // Checks if the current token is the latest version.
    function isLatestVersion(
        uint256 tokenId
    ) external view recordExists(tokenId) returns (bool) {
        SGDRecord storage r = _records[tokenId];
        return latestTokenBySgdId[r.sgdId] == tokenId;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // Record the original owner of the RGD NFT
        // require(msg.sender == address(rgdNftContract), "Only accept from RGDNFT");
        rgdOriginalOwners[tokenId] = from;
        emit RGDReceived(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }

    // TAB BUYER Decrypt
    function tacoCanDecrypt(
        uint256 tokenId,
        address user
    ) external view recordExists(tokenId) returns (uint256) {
        SGDRecord storage r = _records[tokenId];

        // Check: Record active + new version + user wallet purchased transaction completed
        if (r.active && latestTokenBySgdId[r.sgdId] == tokenId && hasPurchased[tokenId][user]) {
            return 1; // Return 1 vs comparator "==" value: 1 in frontend
        }
        return 0;
    }
}