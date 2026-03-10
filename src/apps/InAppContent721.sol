// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

/**
 * @title InAppContent721
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice ERC-721 contract for in-app digital content items.
 * @dev Combines ERC721URIStorage for per-token metadata, ERC-4906 for metadata update signaling,
 *      and ERC-2981 for optional secondary-market royalties. Minting is restricted to an authorized
 *      minter address, typically a ContentStore. Supports contract-level metadata for marketplace
 *      compatibility and emits standard transfer events for indexers.
 */
contract InAppContent721 is ERC721, ERC721URIStorage, ERC2981, Ownable {
    // =========== Errors ===========
    error ZeroAddress();
    error NotMinter();
    error TokenDoesNotExist();
    error InvalidRoyalty();
    error SoulboundTransfer();

    // =========== Events ===========
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event ContractURIUpdated(string oldURI, string newURI);
    event DefaultRoyaltySet(address indexed receiver, uint96 feeNumerator);
    event TokenRoyaltySet(uint256 indexed tokenId, address indexed receiver, uint96 feeNumerator);
    event TokenMetadataUpdated(uint256 indexed tokenId, string uri);
    event SoulboundSet(uint256 indexed tokenId, bool isSoulbound);

    // =========== State ===========

    /// @notice App ID this content belongs to
    uint256 public immutable appId;

    /// @notice Address authorized to mint (typically ContentStore)
    address public minter;

    /// @notice Contract-level metadata URI for OpenSea
    string public contractURI;

    /// @notice Counter for token IDs
    uint256 private _nextTokenId;

    /// @notice Maximum royalty (10% = 1000 bps)
    uint96 public constant MAX_ROYALTY_BPS = 1000;

    /// @notice Tracks which tokens are soulbound (non-transferable)
    mapping(uint256 => bool) public soulbound;

    // =========== Modifiers ===========

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    // =========== Constructor ===========

    /**
     * @notice Create a new in-app content collection
     * @param _appId App ID for attribution
     * @param _name Collection name
     * @param _symbol Collection symbol
     * @param _owner Admin address
     * @param _minter Initial minter (ContentStore)
     * @param _contractURI Contract-level metadata URI
     */
    constructor(
        uint256 _appId,
        string memory _name,
        string memory _symbol,
        address _owner,
        address _minter,
        string memory _contractURI
    ) ERC721(_name, _symbol) Ownable(_owner) {
        // Ownable already validates _owner != address(0)
        appId = _appId;
        minter = _minter;
        contractURI = _contractURI;
    }

    // =========== Minting Functions ===========

    /**
     * @notice Mint a new content item
     * @param to Recipient address
     * @param uri Token metadata URI
     * @return tokenId The minted token ID
     * @dev Only callable by minter (ContentStore)
     */
    function mint(address to, string memory uri) external onlyMinter returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();

        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit TokenMetadataUpdated(tokenId, uri);
    }

    /**
     * @notice Batch mint multiple content items
     * @param to Recipient address
     * @param uris Array of metadata URIs
     * @return tokenIds Array of minted token IDs
     * @dev Only callable by minter (ContentStore)
     */
    function batchMint(address to, string[] memory uris) external onlyMinter returns (uint256[] memory tokenIds) {
        if (to == address(0)) revert ZeroAddress();

        uint256 count = uris.length;
        tokenIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
            tokenIds[i] = tokenId;
            emit TokenMetadataUpdated(tokenId, uris[i]);
        }
    }

    /**
     * @notice Mint a new soulbound (non-transferable) content item
     * @param to Recipient address
     * @param uri Token metadata URI
     * @return tokenId The minted token ID
     * @dev Only callable by minter (ContentStore). Token will be non-transferable.
     */
    function mintSoulbound(address to, string memory uri) external onlyMinter returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();

        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        soulbound[tokenId] = true;

        emit TokenMetadataUpdated(tokenId, uri);
        emit SoulboundSet(tokenId, true);
    }

    /**
     * @notice Batch mint multiple soulbound content items
     * @param to Recipient address
     * @param uris Array of metadata URIs
     * @return tokenIds Array of minted token IDs
     * @dev Only callable by minter (ContentStore). All tokens will be non-transferable.
     */
    function batchMintSoulbound(address to, string[] memory uris)
        external
        onlyMinter
        returns (uint256[] memory tokenIds)
    {
        if (to == address(0)) revert ZeroAddress();

        uint256 count = uris.length;
        tokenIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
            soulbound[tokenId] = true;
            tokenIds[i] = tokenId;
            emit TokenMetadataUpdated(tokenId, uris[i]);
            emit SoulboundSet(tokenId, true);
        }
    }

    // =========== Admin Functions ===========

    /**
     * @notice Set the minter address
     * @param _minter New minter address
     */
    function setMinter(address _minter) external onlyOwner {
        address oldMinter = minter;
        minter = _minter;
        emit MinterUpdated(oldMinter, _minter);
    }

    /**
     * @notice Update contract-level metadata URI
     * @param _contractURI New contract URI
     */
    function setContractURI(string memory _contractURI) external onlyOwner {
        string memory oldURI = contractURI;
        contractURI = _contractURI;
        emit ContractURIUpdated(oldURI, _contractURI);
    }

    /**
     * @notice Update token metadata URI
     * @param tokenId Token to update
     * @param uri New metadata URI
     * @dev Emits ERC-4906 MetadataUpdate for marketplace/indexer refresh
     */
    function setTokenURI(uint256 tokenId, string memory uri) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        _setTokenURI(tokenId, uri);
        emit TokenMetadataUpdated(tokenId, uri);
        emit IERC4906.MetadataUpdate(tokenId);
    }

    /**
     * @notice Batch update token metadata URIs
     * @param tokenIds Array of token IDs to update
     * @param uris Array of new metadata URIs
     * @dev Emits ERC-4906 BatchMetadataUpdate for efficient indexer refresh
     */
    function batchSetTokenURI(uint256[] calldata tokenIds, string[] calldata uris) external onlyOwner {
        require(tokenIds.length == uris.length, "Length mismatch");
        require(tokenIds.length > 0, "Empty array");

        uint256 minId = type(uint256).max;
        uint256 maxId = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
            _setTokenURI(tokenId, uris[i]);
            emit TokenMetadataUpdated(tokenId, uris[i]);

            if (tokenId < minId) minId = tokenId;
            if (tokenId > maxId) maxId = tokenId;
        }

        emit IERC4906.BatchMetadataUpdate(minId, maxId);
    }

    /**
     * @notice Signal metadata refresh for a range of tokens
     * @param fromTokenId Start of token ID range
     * @param toTokenId End of token ID range (inclusive)
     * @dev Useful for off-chain metadata updates (e.g., IPFS re-pin with same CID)
     */
    function emitBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) external onlyOwner {
        emit IERC4906.BatchMetadataUpdate(fromTokenId, toTokenId);
    }

    /**
     * @notice Set or unset soulbound status for a token
     * @param tokenId Token to configure
     * @param _soulbound Whether the token should be non-transferable
     * @dev Only callable by owner. Can be used to lock tokens post-mint or unlock if needed.
     */
    function setSoulbound(uint256 tokenId, bool _soulbound) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        soulbound[tokenId] = _soulbound;
        emit SoulboundSet(tokenId, _soulbound);
    }

    // =========== Royalty Functions ===========

    /**
     * @notice Set default royalty for all tokens
     * @param receiver Royalty recipient
     * @param feeNumerator Royalty in basis points (max 1000 = 10%)
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        if (feeNumerator > MAX_ROYALTY_BPS) revert InvalidRoyalty();
        _setDefaultRoyalty(receiver, feeNumerator);
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    /**
     * @notice Set royalty for a specific token
     * @param tokenId Token to configure
     * @param receiver Royalty recipient
     * @param feeNumerator Royalty in basis points (max 1000 = 10%)
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external onlyOwner {
        if (feeNumerator > MAX_ROYALTY_BPS) revert InvalidRoyalty();
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
        emit TokenRoyaltySet(tokenId, receiver, feeNumerator);
    }

    /**
     * @notice Remove default royalty
     */
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
        emit DefaultRoyaltySet(address(0), 0);
    }

    // =========== View Functions ===========

    /**
     * @notice Get total number of tokens minted
     * @return Total supply
     */
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice Get the next token ID to be minted
     * @return Next token ID
     */
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // =========== Overrides ===========

    /**
     * @dev Override _update to enforce soulbound restrictions
     * Reverts if attempting to transfer a soulbound token (except for minting/burning)
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        // Allow minting (from == 0) and burning (to == 0), block soulbound transfers
        if (from != address(0) && to != address(0) && soulbound[tokenId]) {
            revert SoulboundTransfer();
        }
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC2981)
        returns (bool)
    {
        // ERC-4906 interface ID for metadata update extension
        return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId);
    }
}
