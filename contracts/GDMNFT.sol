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

    enum PipelineStatus { None, Active, Deactivated }

    // Struct RegisterInput: Receive Sub-SGD gene segment registration data.
    struct RegisterInput {
        address initialOwner;
        string sgdId;
        uint256 rgdTokenId;
        string cid;
        string fheEvaluationKeyCID; // FHE evaluation key
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
        uint256 chunkIndex;  // Indexer gen (1, 2, 3...)
        string diseaseTag;   // Pathological label (Blood_Cancer, Kidney_Cancer...)
    }

    // Struct SGDRecord: Save info on Blockchain
    struct SGDRecord 
    {
        uint256 tokenId;
        string sgdId;
        uint256 rgdTokenId;
        string cid;
        string fheEvaluationKeyCID; // FHE evaluation key
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
        uint256 chunkIndex;         // 21
        string diseaseTag;          // 22
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
        uint256 chunkIndex;
        string diseaseTag;
    }

    mapping(uint256 => SGDRecord) private _records;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;

    mapping(uint256 => SGDRecord[]) private _versionsOfSgd;
    mapping(string => uint256) public latestTokenBySgdId;

    // FHE Limited Access: Balance số lượng phép toán
    mapping(uint256 => mapping(address => uint256)) public operationsBalance;

    // Authorized Oracles
    mapping(address => bool) public authorizedOracles;

    // Track original owners of RGD NFTs
    mapping(uint256 => address) public rgdOriginalOwners;

    // Pipeline registry status
    mapping(bytes32 => PipelineStatus) private _pipelineRegistry;

    // token by disease tag mapping
    mapping(string => uint256[]) public tokensByDiseaseTag;

    // Platform fee configuration
    uint256 public platformFeePercentage = 250; // 2.5% = 250 basis points
    address public feeReceiver;

    event RegistrarUpdated(address indexed newRegistrar);
    event RGDReceived(address indexed operator, address indexed from, uint256 indexed tokenId, bytes data);
    event SGDRegistered(
        uint256 indexed tokenId,
        address indexed initialOwner,
        string sgdId,
        string diseaseTag,
        uint256 chunkIndex,
        string cid,
        uint256 price
    );

    event FullAccessPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 amount
    );

    event LimitedAccessPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 operationsNumber,
        uint256 totalCost
    );

    event OperationsBalanceUpdated(
        uint256 indexed tokenId,
        address indexed buyer,
        uint256 remainingOperations
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
    error NotAuthorizedOracle();
    error InsufficientOperationsBalance();

    constructor(address nftAddress, address initialOwner) Ownable(initialOwner) {
        if (nftAddress == address(0)) revert ZeroAddress();
        sgdNft = SGDNFT(nftAddress);
        registrar = initialOwner;
        feeReceiver = initialOwner;
    }

    modifier onlyRegistrar() {
        if (msg.sender != registrar) revert NotRegistrar();
        _;
    }

    modifier recordExists(uint256 tokenId) {
        if (_records[tokenId].tokenId == 0) revert RecordNotFound();
        _;
    }

    modifier onlyRecordOwner(uint256 tokenId) {
        if (msg.sender != sgdNft.ownerOf(tokenId)) revert Unauthorized();
        _;
    }

    modifier onlyOracle() {
        if (!authorizedOracles[msg.sender] && msg.sender != owner()) revert NotAuthorizedOracle();
        _;
    }

    function setOracle(address oracle, bool status) external onlyOwner {
        if (oracle == address(0)) revert ZeroAddress();
        authorizedOracles[oracle] = status;
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

    function getPipelineStatus(uint256 rgdTokenId, string memory sequencingInfo) external view returns (PipelineStatus) {
        bytes32 pipelineHash = keccak256(abi.encodePacked(rgdTokenId, sequencingInfo));
        return _pipelineRegistry[pipelineHash];
    }

    // Đăng ký Sub-SGD NFT chunk
    function registerSGD(RegisterInput calldata input) external onlyRegistrar returns (uint256 tokenId) {
        if (latestTokenBySgdId[input.sgdId] != 0) revert SGDAlreadyRegistered();
        if (input.initialOwner == address(0)) revert ZeroAddress();

        bytes32 pipelineHash = keccak256(abi.encodePacked(input.rgdTokenId, input.sequencingInfo, input.chunkIndex));

        if (_pipelineRegistry[pipelineHash] != PipelineStatus.None) {
            revert SGDAlreadyRegistered();
        }

        tokenId = _nextTokenId;
        _nextTokenId++;

        SGDRecord memory r = SGDRecord({
            tokenId: tokenId,
            sgdId: input.sgdId,
            rgdTokenId: input.rgdTokenId,
            cid: input.cid,
            fheEvaluationKeyCID: input.fheEvaluationKeyCID,
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
            version: 0,
            chunkIndex: input.chunkIndex,
            diseaseTag: input.diseaseTag
        });

        _records[tokenId] = r;
        _pipelineRegistry[pipelineHash] = PipelineStatus.Active;

        // call tokensByDiseaseTag mapping to store tokenId by diseaseTag
        tokensByDiseaseTag[input.diseaseTag].push(tokenId);

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
            input.diseaseTag,
            input.chunkIndex,
            input.cid,
            input.price
        );
    }

    function getPublicRecord(uint256 tokenId) external view recordExists(tokenId) returns (PublicRecord memory) {
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
            active: r.active,
            chunkIndex: r.chunkIndex,
            diseaseTag: r.diseaseTag
        });
    }

    function getFullRecord(uint256 tokenId) external view recordExists(tokenId) returns (SGDRecord memory) {
        return _records[tokenId];
    }

    function getCID(uint256 tokenId) external view recordExists(tokenId) returns (string memory) {
        address currentOwner = sgdNft.ownerOf(tokenId);

        if (
            msg.sender != currentOwner &&
            msg.sender != registrar &&
            msg.sender != owner() &&
            !hasPurchased[tokenId][msg.sender] &&
            operationsBalance[tokenId][msg.sender] == 0
        ) {
            revert Unauthorized();
        }

        return _records[tokenId].cid;
    }

    function purchaseFullAccess(uint256 tokenId) external payable nonReentrant recordExists(tokenId) {
        SGDRecord storage r = _records[tokenId];

        if (!r.active) revert InactiveRecord();
        if (latestTokenBySgdId[r.sgdId] != tokenId) revert NotLatestVersion();
        if (hasPurchased[tokenId][msg.sender]) revert AlreadyPurchased();
        if (msg.value != r.price) revert WrongPayment();

        hasPurchased[tokenId][msg.sender] = true;

        address seller = sgdNft.ownerOf(tokenId);

        uint256 platformFee = (msg.value * platformFeePercentage) / 10000;
        uint256 sellerPayout = msg.value - platformFee;

        if (platformFee > 0) {
            (bool feeOk, ) = payable(feeReceiver).call{value: platformFee}("");
            if (!feeOk) revert PaymentFailed();
        }

        (bool ok, ) = payable(seller).call{value: sellerPayout}("");
        if (!ok) revert PaymentFailed();

        emit FullAccessPurchased(tokenId, msg.sender, msg.value);
    }

    function requestLimitedAccess(
        uint256 tokenId,
        uint256 operationsNumber
    ) external payable nonReentrant recordExists(tokenId) {
        SGDRecord storage r = _records[tokenId];

        if (!r.active) revert InactiveRecord();
        if (latestTokenBySgdId[r.sgdId] != tokenId) revert NotLatestVersion();

        uint256 totalCost = r.price * operationsNumber;
        if (msg.value != totalCost) revert WrongPayment();

        operationsBalance[tokenId][msg.sender] += operationsNumber;

        address seller = sgdNft.ownerOf(tokenId);

        uint256 platformFee = (msg.value * platformFeePercentage) / 10000;
        uint256 sellerPayout = msg.value - platformFee;

        if (platformFee > 0) {
            (bool feeOk, ) = payable(feeReceiver).call{value: platformFee}("");
            if (!feeOk) revert PaymentFailed();
        }

        (bool ok, ) = payable(seller).call{value: sellerPayout}("");
        if (!ok) revert PaymentFailed();

        emit LimitedAccessPurchased(tokenId, msg.sender, operationsNumber, totalCost);
    }

    function updateOperationsBalance(
        uint256 tokenId,
        address buyer,
        uint256 operationsUsed
    ) external onlyOracle recordExists(tokenId) {
       if (operationsBalance[tokenId][buyer] < operationsUsed) {
            revert InsufficientOperationsBalance();
        }

        operationsBalance[tokenId][buyer] -= operationsUsed;
        emit OperationsBalanceUpdated(tokenId, buyer, operationsBalance[tokenId][buyer]);
    }

    function revokeLimitedAccess(uint256 tokenId, address buyer) external recordExists(tokenId) {
        if (msg.sender != registrar && msg.sender != owner() && msg.sender != sgdNft.ownerOf(tokenId)) {
            revert Unauthorized();
        }

        operationsBalance[tokenId][buyer] = 0;
        emit OperationsBalanceUpdated(tokenId, buyer, 0);
    }

    function tacoCanDecrypt(uint256 tokenId, address buyer) external view recordExists(tokenId) returns (uint8) {
        SGDRecord storage r = _records[tokenId];
        bytes32 pipelineHash = keccak256(abi.encodePacked(r.rgdTokenId, r.sequencingInfo, r.chunkIndex));

        if (
            r.active &&
            _pipelineRegistry[pipelineHash] == PipelineStatus.Active &&
            latestTokenBySgdId[r.sgdId] == tokenId &&
            hasPurchased[tokenId][buyer]
        ) {
            return 1;
        }

        return 0;
    }

    function updateSGDVersion(
        uint256 tokenId,
        string calldata newCid, 
        string calldata newAccessCondition,
        uint256 newPrice,
        string calldata newTokenURI,
        address newOwner
    ) external onlyRegistrar recordExists(tokenId) {
        SGDRecord storage record = _records[tokenId];

        if (!record.active) revert InactiveRecord();
        if (latestTokenBySgdId[record.sgdId] != tokenId) revert NotLatestVersion();

        _versionsOfSgd[tokenId].push(record);

        record.cid = newCid;
        record.accessCondition = newAccessCondition;
        record.price = newPrice;
        record.version = record.version + 1;

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
            record.registeredOwner
        );
    }

    function deactivateSGD(uint256 tokenId, address newWalletForActivation) external onlyRecordOwner(tokenId) recordExists(tokenId) {
        if (newWalletForActivation == address(0)) revert ZeroAddress();
        SGDRecord storage record = _records[tokenId];
        if (!record.active) revert InactiveRecord();

        record.active = false;

        bytes32 pipelineHash = keccak256(abi.encodePacked(record.rgdTokenId, record.sequencingInfo, record.chunkIndex));
        _pipelineRegistry[pipelineHash] = PipelineStatus.Deactivated;

        address oldOwner = record.registeredOwner;
        sgdNft.transferByMinter(oldOwner, newWalletForActivation, tokenId);
        record.registeredOwner = newWalletForActivation;

        emit SGDDeactivated(tokenId);

        emit SGDVersionUpdated(
            tokenId,
            record.sgdId,
            record.accessCondition,
            record.price,
            record.version,
            newWalletForActivation
        );
    }

    function activateSGD(uint256 tokenId) external onlyRecordOwner(tokenId) recordExists(tokenId) {
        SGDRecord storage record = _records[tokenId];
        if (record.active) revert("Error: Record is already active");
        if (latestTokenBySgdId[record.sgdId] != tokenId) revert NotLatestVersion();

        record.active = true;

        bytes32 pipelineHash = keccak256(abi.encodePacked(record.rgdTokenId, record.sequencingInfo, record.chunkIndex));
        _pipelineRegistry[pipelineHash] = PipelineStatus.Active;

        record.version = record.version + 1;

        emit SGDVersionUpdated(
            tokenId,
            record.sgdId,
            record.accessCondition,
            record.price,
            record.version,
            record.registeredOwner
        );
    }

    function isSGDPurchasable(string calldata sgdId) external view returns (bool) {
        uint256 latestTokenId = latestTokenBySgdId[sgdId];
        if (latestTokenId == 0) return false;

        SGDRecord storage r = _records[latestTokenId];
        bytes32 pipelineHash = keccak256(abi.encodePacked(r.rgdTokenId, r.sequencingInfo, r.chunkIndex));

        return (
            r.active &&
            _pipelineRegistry[pipelineHash] == PipelineStatus.Active
        );
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    function getVersionsOfSgd(uint256 tokenId) external view returns (SGDRecord[] memory) {
        return _versionsOfSgd[tokenId];
    }

    function isLatestVersion(uint256 tokenId) external view recordExists(tokenId) returns (bool) {
        SGDRecord storage r = _records[tokenId];
        return latestTokenBySgdId[r.sgdId] == tokenId;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        rgdOriginalOwners[tokenId] = from;
        emit RGDReceived(operator, from, tokenId, data);
        return this.onERC721Received.selector;
    }
}