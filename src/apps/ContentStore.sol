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
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Primary sales contract for in-app digital content.
 * @dev Manages content listings with prices and metadata URIs. Users purchase items with app tokens,
 *      triggering a mint on the linked InAppContent721 contract. A configurable portion of each sale
 *      routes to FeeCollector for protocol fees; the remainder goes to the creator. Supports time
 *      windows and feature gates for content availability.
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
    error PurchaseTooEarly();
    error PurchaseTooLate();
    error InvalidTimeWindow();

    // =========== Events ===========
    event ContentListed(uint256 indexed contentId, string uri, uint256 price, uint256 maxSupply);
    event ContentListedWithTimeWindow(
        uint256 indexed contentId, string uri, uint256 price, uint256 maxSupply, uint64 startTime, uint64 endTime
    );
    event ContentPurchased(
        uint256 indexed contentId, address indexed buyer, uint256 tokenId, uint256 price, uint256 protocolFee
    );
    event ContentDeactivated(uint256 indexed contentId);
    event ContentReactivated(uint256 indexed contentId);
    event ProtocolFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    event RevenueWithdrawn(address indexed to, uint256 amount);
    event BurnBpsUpdated(uint256 oldBps, uint256 newBps);
    event FeatureGateSet(
        bytes32 indexed featureId, uint256 minStake, uint256 requiredContentId, bool requireBoth, bool active
    );
    event ContentTimeWindowUpdated(uint256 indexed contentId, uint64 startTime, uint64 endTime);

    // =========== Structs ===========

    struct Content {
        string uri; // Metadata URI for minted tokens
        uint256 price; // Price in payment token
        uint256 maxSupply; // 0 = unlimited
        uint256 minted; // Count of purchases
        bool active; // Whether available for purchase
        PaymentTokenType paymentType; // Which token to accept
        uint64 startTime; // 0 = always available
        uint64 endTime; // 0 = no end time
    }

    struct FeatureGate {
        uint256 minStake; // Minimum stake required (checked app-side)
        uint256 requiredContentId; // Content ID required (0 = none)
        bool requireBoth; // If true: stake AND content; else stake OR content
        bool active; // Gate enabled
    }

    /// @notice Configuration struct for ContentStore initialization
    struct InitConfig {
        uint256 appId;
        address appToken;
        address elta;
        address usdc;
        address treasury;
        address content721;
        address admin;
        address feeCollector;
        uint256 protocolFeeBps;
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

    /// @notice Feature gates by feature ID
    mapping(bytes32 => FeatureGate) public gates;

    // =========== Constructor ===========

    /**
     * @notice Create a new content store
     * @param config Initialization configuration struct
     */
    constructor(InitConfig memory config) {
        if (config.appToken == address(0)) revert ZeroAddress();
        if (config.content721 == address(0)) revert ZeroAddress();
        if (config.protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert InvalidFeeBps();

        appId = config.appId;
        appToken = IERC20(config.appToken);
        elta = IERC20(config.elta);
        usdc = IERC20(config.usdc);
        treasury = config.treasury;
        content721 = IInAppContent721(config.content721);
        feeCollector = config.feeCollector;
        protocolFeeBps = config.protocolFeeBps;

        // Grant roles to admin
        _grantRole(DEFAULT_ADMIN_ROLE, config.admin);
        _grantRole(MODULE_ADMIN_ROLE, config.admin);
        _grantRole(MODULE_OPERATOR_ROLE, config.admin);
    }

    // =========== Listing Functions ===========

    /**
     * @notice List new content for sale (always available)
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
        contents[contentId] = Content({
            uri: uri,
            price: price,
            maxSupply: maxSupply,
            minted: 0,
            active: true,
            paymentType: paymentType,
            startTime: 0,
            endTime: 0
        });

        emit ContentListed(contentId, uri, price, maxSupply);
    }

    /**
     * @notice List new content for sale with time window
     * @param uri Metadata URI
     * @param price Price in payment token
     * @param maxSupply Maximum purchases (0 = unlimited)
     * @param paymentType Which token type to accept (APP, ELTA, USDC)
     * @param startTime Sale start time (0 = always available)
     * @param endTime Sale end time (0 = no end)
     * @return contentId The new content ID
     */
    function listContentWithTimeWindow(
        string memory uri,
        uint256 price,
        uint256 maxSupply,
        PaymentTokenType paymentType,
        uint64 startTime,
        uint64 endTime
    ) external onlyRole(MODULE_OPERATOR_ROLE) returns (uint256 contentId) {
        if (price == 0) revert ZeroPrice();
        if (endTime != 0 && startTime >= endTime) revert InvalidTimeWindow();

        contentId = nextContentId++;
        contents[contentId] = Content({
            uri: uri,
            price: price,
            maxSupply: maxSupply,
            minted: 0,
            active: true,
            paymentType: paymentType,
            startTime: startTime,
            endTime: endTime
        });

        emit ContentListedWithTimeWindow(contentId, uri, price, maxSupply, startTime, endTime);
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
        if (content.startTime != 0 && block.timestamp < content.startTime) {
            revert PurchaseTooEarly();
        }
        if (content.endTime != 0 && block.timestamp > content.endTime) {
            revert PurchaseTooLate();
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

    /**
     * @notice Update time window for content listing
     * @param contentId Content to update
     * @param startTime New start time (0 = always available)
     * @param endTime New end time (0 = no end)
     */
    function setContentTimeWindow(uint256 contentId, uint64 startTime, uint64 endTime)
        external
        onlyRole(MODULE_OPERATOR_ROLE)
    {
        if (contentId >= nextContentId) revert ContentDoesNotExist();
        if (endTime != 0 && startTime >= endTime) revert InvalidTimeWindow();

        contents[contentId].startTime = startTime;
        contents[contentId].endTime = endTime;

        emit ContentTimeWindowUpdated(contentId, startTime, endTime);
    }

    // =========== Feature Gate Functions ===========

    /**
     * @notice Set or update a feature gate
     * @param featureId Unique identifier for the feature
     * @param minStake Minimum stake required (0 = no stake requirement)
     * @param requiredContentId Content ID required to have purchased (0 = no content requirement)
     * @param requireBoth If true: need both stake AND content; if false: stake OR content
     * @param active Whether the gate is active
     */
    function setFeatureGate(
        bytes32 featureId,
        uint256 minStake,
        uint256 requiredContentId,
        bool requireBoth,
        bool active
    ) external onlyRole(MODULE_OPERATOR_ROLE) {
        gates[featureId] = FeatureGate({
            minStake: minStake, requiredContentId: requiredContentId, requireBoth: requireBoth, active: active
        });

        emit FeatureGateSet(featureId, minStake, requiredContentId, requireBoth, active);
    }

    /**
     * @notice Check if a user has access to a feature
     * @param featureId Feature identifier
     * @param userStake User's current stake amount (pass from StakingVault)
     * @param userContentBalance User's balance of the required content (pass from InAppContent721)
     * @return hasAccess Whether user meets requirements
     * @dev First parameter (user address) reserved for future on-chain lookups
     */
    function checkFeatureAccess(
        address,
        /* user */
        bytes32 featureId,
        uint256 userStake,
        uint256 userContentBalance
    )
        external
        view
        returns (bool hasAccess)
    {
        FeatureGate memory gate = gates[featureId];

        if (!gate.active) return false;

        bool meetsStake = userStake >= gate.minStake;
        bool hasContent = gate.requiredContentId > 0 && userContentBalance > 0;

        // If no content required (requiredContentId == 0), only check stake
        if (gate.requiredContentId == 0) return meetsStake;

        // If content required, apply AND/OR logic
        if (gate.requireBoth) return meetsStake && hasContent;
        else return meetsStake || hasContent;
    }

    // =========== View Functions ===========

    /**
     * @notice Get content details
     * @param contentId Content ID
     * @return content The content struct with all details
     */
    function getContent(uint256 contentId) external view returns (Content memory content) {
        return contents[contentId];
    }

    /**
     * @notice Get basic content details (backwards compatible)
     * @param contentId Content ID
     * @return uri Metadata URI
     * @return price Price in payment token
     * @return maxSupply Maximum supply (0 = unlimited)
     * @return minted Number minted
     * @return active Whether available for purchase
     * @return paymentType Which token type is accepted
     */
    function getContentBasic(uint256 contentId)
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
     * @return reason Reason code (0=can buy, 1=doesn't exist, 2=not active, 3=sold out, 4=too early, 5=too late)
     */
    function canPurchase(uint256 contentId) external view returns (bool canPurchase_, uint8 reason) {
        if (contentId >= nextContentId) return (false, 1);

        Content storage content = contents[contentId];
        if (!content.active) return (false, 2);
        if (content.maxSupply > 0 && content.minted >= content.maxSupply) return (false, 3);
        if (content.startTime != 0 && block.timestamp < content.startTime) return (false, 4);
        if (content.endTime != 0 && block.timestamp > content.endTime) return (false, 5);

        return (true, 0);
    }

    /**
     * @notice Get feature gate details
     * @param featureId Feature identifier
     * @return minStake Minimum stake required
     * @return requiredContentId Content ID required
     * @return requireBoth Whether both conditions are required
     * @return active Whether gate is active
     */
    function getFeatureGate(bytes32 featureId)
        external
        view
        returns (uint256 minStake, uint256 requiredContentId, bool requireBoth, bool active)
    {
        FeatureGate memory gate = gates[featureId];
        return (gate.minStake, gate.requiredContentId, gate.requireBoth, gate.active);
    }

    /**
     * @notice Get total content count
     * @return Number of content listings
     */
    function contentCount() external view returns (uint256) {
        return nextContentId;
    }
}
