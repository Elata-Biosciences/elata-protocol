// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Interface for InAppContent721
interface IInAppContent721 {
    function mint(address to, string memory uri) external returns (uint256 tokenId);
}

/// @notice Interface for FeeCollector
interface IFeeCollector {
    function depositAppToken(uint256 appId, address token, uint256 amount) external;
}

/**
 * @title ContentStore
 * @author Elata Protocol
 * @notice Primary sales mechanism for in-app content
 * @dev Handles purchases and fee routing for InAppContent721 tokens
 *
 * Per Protocol Changes document:
 * - Accept app token by default
 * - Optional ELTA/USDC support later
 * - Route configurable share to fee pipeline
 * - No burn by default (can add burnBps later)
 *
 * Key Features:
 * - Define content listings with price and metadata URI
 * - Users purchase content with app tokens
 * - Automatic fee split to protocol and creator
 * - Integration with FeeCollector for protocol fees
 */
contract ContentStore is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error ZeroPrice();
    error ContentNotActive();
    error ContentDoesNotExist();
    error InsufficientPayment();
    error InvalidFeeBps();
    error MaxSupplyReached();

    // =========== Events ===========
    event ContentListed(uint256 indexed contentId, string uri, uint256 price, uint256 maxSupply);
    event ContentPurchased(
        uint256 indexed contentId, address indexed buyer, uint256 tokenId, uint256 price, uint256 protocolFee
    );
    event ContentDeactivated(uint256 indexed contentId);
    event ContentReactivated(uint256 indexed contentId);
    event ProtocolFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    event RevenueWithdrawn(address indexed to, uint256 amount);

    // =========== Structs ===========

    struct Content {
        string uri; // Metadata URI for minted tokens
        uint256 price; // Price in app tokens
        uint256 maxSupply; // 0 = unlimited
        uint256 minted; // Count of purchases
        bool active; // Whether available for purchase
    }

    // =========== State ===========

    /// @notice App ID for fee routing
    uint256 public immutable appId;

    /// @notice App token for payments
    IERC20 public immutable appToken;

    /// @notice InAppContent721 contract to mint to
    IInAppContent721 public immutable content721;

    /// @notice FeeCollector for protocol fees
    address public feeCollector;

    /// @notice Protocol fee in basis points (e.g., 500 = 5%)
    uint256 public protocolFeeBps;

    /// @notice Maximum protocol fee (15%)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1500;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Content listings
    mapping(uint256 => Content) public contents;

    /// @notice Next content ID
    uint256 public nextContentId;

    /// @notice Accumulated creator revenue
    uint256 public creatorRevenue;

    // =========== Constructor ===========

    /**
     * @notice Create a new content store
     * @param _appId App ID for fee routing
     * @param _appToken App token for payments
     * @param _content721 InAppContent721 contract
     * @param _owner Store admin (typically app creator)
     * @param _feeCollector FeeCollector for protocol fees
     * @param _protocolFeeBps Initial protocol fee in bps
     */
    constructor(
        uint256 _appId,
        address _appToken,
        address _content721,
        address _owner,
        address _feeCollector,
        uint256 _protocolFeeBps
    ) Ownable(_owner) {
        if (_appToken == address(0)) revert ZeroAddress();
        if (_content721 == address(0)) revert ZeroAddress();
        if (_protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidFeeBps();

        appId = _appId;
        appToken = IERC20(_appToken);
        content721 = IInAppContent721(_content721);
        feeCollector = _feeCollector;
        protocolFeeBps = _protocolFeeBps;
    }

    // =========== Listing Functions ===========

    /**
     * @notice List new content for sale
     * @param uri Metadata URI
     * @param price Price in app tokens
     * @param maxSupply Maximum purchases (0 = unlimited)
     * @return contentId The new content ID
     */
    function listContent(string memory uri, uint256 price, uint256 maxSupply)
        external
        onlyOwner
        returns (uint256 contentId)
    {
        if (price == 0) revert ZeroPrice();

        contentId = nextContentId++;
        contents[contentId] = Content({uri: uri, price: price, maxSupply: maxSupply, minted: 0, active: true});

        emit ContentListed(contentId, uri, price, maxSupply);
    }

    /**
     * @notice Deactivate content listing
     * @param contentId Content to deactivate
     */
    function deactivateContent(uint256 contentId) external onlyOwner {
        if (contentId >= nextContentId) revert ContentDoesNotExist();
        contents[contentId].active = false;
        emit ContentDeactivated(contentId);
    }

    /**
     * @notice Reactivate content listing
     * @param contentId Content to reactivate
     */
    function reactivateContent(uint256 contentId) external onlyOwner {
        if (contentId >= nextContentId) revert ContentDoesNotExist();
        contents[contentId].active = true;
        emit ContentReactivated(contentId);
    }

    // =========== Purchase Functions ===========

    /**
     * @notice Purchase content and receive minted token
     * @param contentId Content to purchase
     * @return tokenId The minted token ID
     * @dev User must approve this contract for app tokens first
     */
    function purchase(uint256 contentId) external nonReentrant returns (uint256 tokenId) {
        Content storage content = contents[contentId];

        if (contentId >= nextContentId) revert ContentDoesNotExist();
        if (!content.active) revert ContentNotActive();
        if (content.maxSupply > 0 && content.minted >= content.maxSupply) {
            revert MaxSupplyReached();
        }

        uint256 price = content.price;

        // Collect payment
        appToken.safeTransferFrom(msg.sender, address(this), price);

        // Calculate and route protocol fee
        uint256 protocolFee = (price * protocolFeeBps) / BPS;
        if (protocolFee > 0 && feeCollector != address(0)) {
            appToken.approve(feeCollector, protocolFee);
            IFeeCollector(feeCollector).depositAppToken(appId, address(appToken), protocolFee);
        } else {
            // If no fee collector, all goes to creator
            protocolFee = 0;
        }

        // Remaining goes to creator revenue
        creatorRevenue += price - protocolFee;

        // Increment minted count
        content.minted++;

        // Mint token to buyer
        tokenId = content721.mint(msg.sender, content.uri);

        emit ContentPurchased(contentId, msg.sender, tokenId, price, protocolFee);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Withdraw accumulated creator revenue
     * @param to Recipient address
     */
    function withdrawRevenue(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        uint256 amount = creatorRevenue;
        creatorRevenue = 0;

        appToken.safeTransfer(to, amount);

        emit RevenueWithdrawn(to, amount);
    }

    /**
     * @notice Set protocol fee
     * @param newBps New fee in basis points
     */
    function setProtocolFeeBps(uint256 newBps) external onlyOwner {
        if (newBps > MAX_PROTOCOL_FEE_BPS) revert InvalidFeeBps();

        uint256 oldBps = protocolFeeBps;
        protocolFeeBps = newBps;

        emit ProtocolFeeBpsUpdated(oldBps, newBps);
    }

    /**
     * @notice Set fee collector address
     * @param _feeCollector New fee collector
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        address oldCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldCollector, _feeCollector);
    }

    // =========== View Functions ===========

    /**
     * @notice Get content details
     * @param contentId Content ID
     * @return uri Metadata URI
     * @return price Price in app tokens
     * @return maxSupply Maximum supply (0 = unlimited)
     * @return minted Number minted
     * @return active Whether available for purchase
     */
    function getContent(uint256 contentId)
        external
        view
        returns (string memory uri, uint256 price, uint256 maxSupply, uint256 minted, bool active)
    {
        Content storage content = contents[contentId];
        return (content.uri, content.price, content.maxSupply, content.minted, content.active);
    }

    /**
     * @notice Check if content can be purchased
     * @param contentId Content ID
     * @return canPurchase_ Whether purchase is possible
     * @return reason Reason code (0=can buy, 1=doesn't exist, 2=not active, 3=sold out)
     */
    function canPurchase(uint256 contentId) external view returns (bool canPurchase_, uint8 reason) {
        if (contentId >= nextContentId) return (false, 1);

        Content storage content = contents[contentId];
        if (!content.active) return (false, 2);
        if (content.maxSupply > 0 && content.minted >= content.maxSupply) return (false, 3);

        return (true, 0);
    }

    /**
     * @notice Get total content count
     * @return Number of content listings
     */
    function contentCount() external view returns (uint256) {
        return nextContentId;
    }
}
