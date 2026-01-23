// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Interface for InAppContent721
interface IInAppContent721 {
    function mint(address to, string memory uri) external returns (uint256 tokenId);
}

/// @notice Interface for FeeCollector
interface IFeeCollector {
    function depositAppToken(uint256 appId, address token, uint256 amount) external;
    function depositElta(uint256 appId, uint256 amount) external;
}

/// @notice Supported payment token types
enum PaymentTokenType {
    APP, // App token (default)
    ELTA, // ELTA token
    USDC // USDC stablecoin
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
contract ContentStore is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Module admin role - can manage settings and withdraw
    bytes32 public constant MODULE_ADMIN_ROLE = keccak256("MODULE_ADMIN_ROLE");

    /// @notice Module operator role - can manage content listings
    bytes32 public constant MODULE_OPERATOR_ROLE = keccak256("MODULE_OPERATOR_ROLE");

    // =========== Errors ===========
    error ZeroAddress();
    error ZeroPrice();
    error ContentNotActive();
    error ContentDoesNotExist();
    error InsufficientPayment();
    error InvalidFeeBps();
    error InvalidBurnBps();
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
    event BurnBpsUpdated(uint256 oldBps, uint256 newBps);

    // =========== Structs ===========

    struct Content {
        string uri; // Metadata URI for minted tokens
        uint256 price; // Price in payment token
        uint256 maxSupply; // 0 = unlimited
        uint256 minted; // Count of purchases
        bool active; // Whether available for purchase
        PaymentTokenType paymentType; // Which token to accept
    }

    // =========== State ===========

    /// @notice App ID for fee routing
    uint256 public immutable appId;

    /// @notice App token for payments
    IERC20 public immutable appToken;

    /// @notice ELTA token for payments
    IERC20 public immutable elta;

    /// @notice USDC token for payments
    IERC20 public immutable usdc;

    /// @notice Protocol treasury for USDC fees
    address public immutable treasury;

    /// @notice InAppContent721 contract to mint to
    IInAppContent721 public immutable content721;

    /// @notice FeeCollector for protocol fees
    address public feeCollector;

    /// @notice Protocol fee in basis points (e.g., 500 = 5%)
    uint256 public protocolFeeBps;

    /// @notice Maximum protocol fee (15%)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1500;

    /// @notice Optional burn fee in basis points (portion of purchase burned)
    uint256 public burnBps = 0;

    /// @notice Maximum burn fee (5%)
    uint256 public constant MAX_BURN_BPS = 500;

    /// @notice Burn sink address for deflationary mechanism
    address public constant BURN_SINK = 0x000000000000000000000000000000000000dEaD;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Content listings
    mapping(uint256 => Content) public contents;

    /// @notice Next content ID
    uint256 public nextContentId;

    /// @notice Accumulated creator revenue per payment type
    mapping(PaymentTokenType => uint256) public creatorRevenue;

    // =========== Constructor ===========

    /**
     * @notice Create a new content store
     * @param _appId App ID for fee routing
     * @param _appToken App token for payments
     * @param _elta ELTA token for payments
     * @param _usdc USDC token for payments
     * @param _treasury Protocol treasury for USDC fees
     * @param _content721 InAppContent721 contract
     * @param _admin Store admin (typically app creator)
     * @param _feeCollector FeeCollector for protocol fees
     * @param _protocolFeeBps Initial protocol fee in bps
     */
    constructor(
        uint256 _appId,
        address _appToken,
        address _elta,
        address _usdc,
        address _treasury,
        address _content721,
        address _admin,
        address _feeCollector,
        uint256 _protocolFeeBps
    ) {
        if (_appToken == address(0)) revert ZeroAddress();
        if (_content721 == address(0)) revert ZeroAddress();
        if (_protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidFeeBps();

        appId = _appId;
        appToken = IERC20(_appToken);
        elta = IERC20(_elta);
        usdc = IERC20(_usdc);
        treasury = _treasury;
        content721 = IInAppContent721(_content721);
        feeCollector = _feeCollector;
        protocolFeeBps = _protocolFeeBps;

        // Grant roles to admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MODULE_ADMIN_ROLE, _admin);
        _grantRole(MODULE_OPERATOR_ROLE, _admin);
    }

    // =========== Listing Functions ===========

    /**
     * @notice List new content for sale
     * @param uri Metadata URI
     * @param price Price in payment token
     * @param maxSupply Maximum purchases (0 = unlimited)
     * @param paymentType Which token type to accept (APP, ELTA, USDC)
     * @return contentId The new content ID
     */
    function listContent(string memory uri, uint256 price, uint256 maxSupply, PaymentTokenType paymentType)
        external
        onlyRole(MODULE_OPERATOR_ROLE)
        returns (uint256 contentId)
    {
        if (price == 0) revert ZeroPrice();

        contentId = nextContentId++;
        contents[contentId] =
            Content({uri: uri, price: price, maxSupply: maxSupply, minted: 0, active: true, paymentType: paymentType});

        emit ContentListed(contentId, uri, price, maxSupply);
    }

    /**
     * @notice Deactivate content listing
     * @param contentId Content to deactivate
     */
    function deactivateContent(uint256 contentId) external onlyRole(MODULE_OPERATOR_ROLE) {
        if (contentId >= nextContentId) revert ContentDoesNotExist();
        contents[contentId].active = false;
        emit ContentDeactivated(contentId);
    }

    /**
     * @notice Reactivate content listing
     * @param contentId Content to reactivate
     */
    function reactivateContent(uint256 contentId) external onlyRole(MODULE_OPERATOR_ROLE) {
        if (contentId >= nextContentId) revert ContentDoesNotExist();
        contents[contentId].active = true;
        emit ContentReactivated(contentId);
    }

    // =========== Purchase Functions ===========

    /**
     * @notice Purchase content and receive minted token
     * @param contentId Content to purchase
     * @return tokenId The minted token ID
     * @dev User must approve this contract for payment tokens first
     */
    function purchase(uint256 contentId) external nonReentrant returns (uint256 tokenId) {
        Content storage content = contents[contentId];

        if (contentId >= nextContentId) revert ContentDoesNotExist();
        if (!content.active) revert ContentNotActive();
        if (content.maxSupply > 0 && content.minted >= content.maxSupply) {
            revert MaxSupplyReached();
        }

        uint256 price = content.price;
        PaymentTokenType paymentType = content.paymentType;

        // Get the appropriate payment token
        IERC20 paymentToken = _getPaymentToken(paymentType);

        // Collect payment
        paymentToken.safeTransferFrom(msg.sender, address(this), price);

        // Calculate and apply burn (if enabled)
        uint256 burnAmount = 0;
        if (burnBps > 0) {
            burnAmount = (price * burnBps) / BPS;
            if (burnAmount > 0) {
                paymentToken.safeTransfer(BURN_SINK, burnAmount);
            }
        }

        // Calculate and route protocol fee (from remaining amount)
        uint256 remainingAfterBurn = price - burnAmount;
        uint256 protocolFee = (remainingAfterBurn * protocolFeeBps) / BPS;
        if (protocolFee > 0 && _canRouteProtocolFee(paymentType)) {
            _routeProtocolFee(paymentType, paymentToken, protocolFee);
        } else {
            // If no fee collector, all goes to creator
            protocolFee = 0;
        }

        // Remaining goes to creator revenue
        creatorRevenue[paymentType] += remainingAfterBurn - protocolFee;

        // Increment minted count
        content.minted++;

        // Mint token to buyer
        tokenId = content721.mint(msg.sender, content.uri);

        emit ContentPurchased(contentId, msg.sender, tokenId, price, protocolFee);
    }

    /**
     * @dev Check if protocol fee can be routed for a given payment type
     */
    function _canRouteProtocolFee(PaymentTokenType paymentType) internal view returns (bool) {
        if (paymentType == PaymentTokenType.APP || paymentType == PaymentTokenType.ELTA) {
            return feeCollector != address(0);
        } else {
            // USDC goes to treasury
            return treasury != address(0);
        }
    }

    /**
     * @dev Get the payment token for a given type
     */
    function _getPaymentToken(PaymentTokenType paymentType) internal view returns (IERC20) {
        if (paymentType == PaymentTokenType.APP) {
            return appToken;
        } else if (paymentType == PaymentTokenType.ELTA) {
            return elta;
        } else {
            return usdc;
        }
    }

    /**
     * @dev Route protocol fee to FeeCollector or treasury
     */
    function _routeProtocolFee(PaymentTokenType paymentType, IERC20 token, uint256 amount) internal {
        if (paymentType == PaymentTokenType.APP) {
            if (feeCollector != address(0)) {
                token.approve(feeCollector, amount);
                IFeeCollector(feeCollector).depositAppToken(appId, address(token), amount);
            }
        } else if (paymentType == PaymentTokenType.ELTA) {
            if (feeCollector != address(0)) {
                token.approve(feeCollector, amount);
                IFeeCollector(feeCollector).depositElta(appId, amount);
            }
        } else {
            // USDC goes directly to treasury
            if (treasury != address(0)) {
                token.safeTransfer(treasury, amount);
            }
        }
    }

    // =========== Admin Functions ===========

    /**
     * @notice Withdraw accumulated creator revenue for a specific token type
     * @param to Recipient address
     * @param paymentType Which revenue type to withdraw (APP, ELTA, USDC)
     */
    function withdrawRevenue(address to, PaymentTokenType paymentType)
        external
        onlyRole(MODULE_ADMIN_ROLE)
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();

        uint256 amount = creatorRevenue[paymentType];
        creatorRevenue[paymentType] = 0;

        IERC20 token = _getPaymentToken(paymentType);
        token.safeTransfer(to, amount);

        emit RevenueWithdrawn(to, amount);
    }

    /**
     * @notice Set protocol fee
     * @param newBps New fee in basis points
     */
    function setProtocolFeeBps(uint256 newBps) external onlyRole(MODULE_ADMIN_ROLE) {
        if (newBps > MAX_PROTOCOL_FEE_BPS) revert InvalidFeeBps();

        uint256 oldBps = protocolFeeBps;
        protocolFeeBps = newBps;

        emit ProtocolFeeBpsUpdated(oldBps, newBps);
    }

    /**
     * @notice Set fee collector address
     * @param _feeCollector New fee collector
     */
    function setFeeCollector(address _feeCollector) external onlyRole(MODULE_ADMIN_ROLE) {
        address oldCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldCollector, _feeCollector);
    }

    /**
     * @notice Set burn fee for content purchases
     * @param newBps New burn fee in basis points (max 5%)
     */
    function setBurnBps(uint256 newBps) external onlyRole(MODULE_ADMIN_ROLE) {
        if (newBps > MAX_BURN_BPS) revert InvalidBurnBps();
        uint256 oldBps = burnBps;
        burnBps = newBps;
        emit BurnBpsUpdated(oldBps, newBps);
    }

    // =========== View Functions ===========

    /**
     * @notice Get content details
     * @param contentId Content ID
     * @return uri Metadata URI
     * @return price Price in payment token
     * @return maxSupply Maximum supply (0 = unlimited)
     * @return minted Number minted
     * @return active Whether available for purchase
     * @return paymentType Which token type is accepted
     */
    function getContent(uint256 contentId)
        external
        view
        returns (
            string memory uri,
            uint256 price,
            uint256 maxSupply,
            uint256 minted,
            bool active,
            PaymentTokenType paymentType
        )
    {
        Content storage content = contents[contentId];
        return (content.uri, content.price, content.maxSupply, content.minted, content.active, content.paymentType);
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
