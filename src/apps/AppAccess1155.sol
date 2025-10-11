// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IAppToken } from "./Interfaces.sol";

/**
 * @title AppAccess1155
 * @author Elata Protocol
 * @notice In-app items and passes with burn-on-purchase mechanics
 * @dev ERC1155 for app items/passes with SBT support and feature gating
 *
 * Key Features:
 * - Configurable items: price, soulbound toggle, time windows, supply caps
 * - 100% burn-on-purchase (deflationary by design)
 * - Soulbound (non-transferable) toggle per item
 * - Feature gate registry for app-side enforcement
 * - View-rich interface for easy indexing
 *
 * Usage:
 * 1. Owner configures items with setItem()
 * 2. Users purchase items (burns app tokens)
 * 3. Apps read feature gates and balances for access control
 */
contract AppAccess1155 is ERC1155, Ownable, ReentrancyGuard {
    struct Item {
        uint256 price; // per unit in app tokens
        bool soulbound; // non-transferable if true
        bool active; // purchase enabled
        uint64 startTime; // 0 => always available
        uint64 endTime; // 0 => no end
        uint64 maxSupply; // 0 => unbounded
        uint64 minted; // running total
        string uri_; // per-ID URI
    }

    struct FeatureGate {
        uint256 minStake; // staking threshold (checked app-side)
        uint256 requiredItem; // item ID required (0 = none)
        bool requireBoth; // if true: stake AND item; else stake OR item
        bool active; // gate enabled
    }

    /// @notice App token used for purchases (burned on purchase)
    IAppToken public immutable APP;

    /// @notice Staking vault address (for feature gate checks)
    address public immutable STAKING;

    /// @notice Item configurations by ID
    mapping(uint256 => Item) public items;

    /// @notice Per-item URI overrides
    mapping(uint256 => string) private _idURIs;

    /// @notice Feature gates by feature ID
    mapping(bytes32 => FeatureGate) public gates;

    event ItemConfigured(uint256 indexed id, Item item);
    event Purchased(address indexed user, uint256 indexed id, uint256 amount, uint256 cost);
    event SoulboundToggled(uint256 indexed id, bool soulbound);
    event FeatureGateSet(bytes32 indexed featureId, FeatureGate gate);

    error ItemInactive();
    error PurchaseTooEarly();
    error PurchaseTooLate();
    error SupplyExceeded();
    error SoulboundTransfer();

    /**
     * @notice Initialize access control contract
     * @param appToken Address of the app ERC20 token
     * @param stakingVault Address of staking vault (0 if unused)
     * @param owner_ Contract owner (app creator)
     * @param baseURI Base URI for ERC1155 metadata
     */
    constructor(address appToken, address stakingVault, address owner_, string memory baseURI)
        ERC1155(baseURI)
        Ownable(owner_)
    {
        APP = IAppToken(appToken);
        STAKING = stakingVault;
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN CONFIGURATION
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Configure or update an item
     * @param id Item ID
     * @param price Price per unit in app tokens
     * @param soulbound Whether item is non-transferable
     * @param active Whether item is available for purchase
     * @param startTime Sale start time (0 = always)
     * @param endTime Sale end time (0 = no end)
     * @param maxSupply Maximum supply (0 = unbounded)
     * @param perIdURI Metadata URI for this item
     */
    function setItem(
        uint256 id,
        uint256 price,
        bool soulbound,
        bool active,
        uint64 startTime,
        uint64 endTime,
        uint64 maxSupply,
        string calldata perIdURI
    ) external onlyOwner {
        items[id] = Item({
            price: price,
            soulbound: soulbound,
            active: active,
            startTime: startTime,
            endTime: endTime,
            maxSupply: maxSupply,
            minted: items[id].minted, // preserve minted count
            uri_: perIdURI
        });
        _idURIs[id] = perIdURI;
        emit ItemConfigured(id, items[id]);
    }

    /**
     * @notice Toggle item active status
     * @param id Item ID
     * @param active New active status
     */
    function setItemActive(uint256 id, bool active) external onlyOwner {
        items[id].active = active;
        emit ItemConfigured(id, items[id]);
    }

    /**
     * @notice Toggle soulbound status for an item
     * @param id Item ID
     * @param soulbound New soulbound status
     */
    function toggleSoulbound(uint256 id, bool soulbound) external onlyOwner {
        items[id].soulbound = soulbound;
        emit SoulboundToggled(id, soulbound);
    }

    /**
     * @notice Set or update a feature gate
     * @param featureId Unique identifier for the feature
     * @param gate Gate configuration
     */
    function setFeatureGate(bytes32 featureId, FeatureGate calldata gate) external onlyOwner {
        gates[featureId] = gate;
        emit FeatureGateSet(featureId, gate);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PURCHASE (BURN-ON-PURCHASE)
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Purchase items by burning app tokens
     * @dev User must approve this contract for APP tokens first
     * @param id Item ID to purchase
     * @param amount Quantity to purchase
     */
    function purchase(uint256 id, uint256 amount, bytes32 /* reason */ ) external nonReentrant {
        Item memory it = items[id];

        // Validate purchase conditions
        if (!it.active) revert ItemInactive();
        if (it.startTime != 0 && block.timestamp < it.startTime) {
            revert PurchaseTooEarly();
        }
        if (it.endTime != 0 && block.timestamp > it.endTime) {
            revert PurchaseTooLate();
        }
        if (it.maxSupply != 0 && it.minted + amount > it.maxSupply) {
            revert SupplyExceeded();
        }

        uint256 cost = it.price * amount;

        // Burn 100% of payment (deflationary)
        APP.burnFrom(msg.sender, cost);

        // Mint items to user
        _mint(msg.sender, id, amount, "");
        items[id].minted += uint64(amount);

        emit Purchased(msg.sender, id, amount, cost);
        // NOTE: reason is emitted for off-chain tracking (e.g., XP integration)
    }

    // ────────────────────────────────────────────────────────────────────────────
    // SOULBOUND ENFORCEMENT
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Enforce soulbound restrictions on transfers
     * @dev Reverts if attempting to transfer a soulbound item
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        // Allow minting (from == 0) and burning (to == 0)
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                if (items[ids[i]].soulbound) {
                    revert SoulboundTransfer();
                }
            }
        }
        super._update(from, to, ids, values);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // VIEWS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get metadata URI for a specific item
     * @param id Item ID
     * @return Metadata URI
     */
    function uri(uint256 id) public view override returns (string memory) {
        string memory per = _idURIs[id];
        return bytes(per).length > 0 ? per : super.uri(id);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ENHANCED VIEW FUNCTIONS FOR UI/UX
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Check if a user has access to a feature
     * @param user User address to check
     * @param featureId Feature identifier
     * @param userStake User's current stake amount (pass from StakingVault)
     * @return hasAccess Whether user meets requirements
     */
    function checkFeatureAccess(address user, bytes32 featureId, uint256 userStake)
        external
        view
        returns (bool hasAccess)
    {
        FeatureGate memory gate = gates[featureId];

        if (!gate.active) return false;

        bool meetsStake = userStake >= gate.minStake;
        bool hasItem = gate.requiredItem > 0 && balanceOf(user, gate.requiredItem) > 0;

        // If no item required (requiredItem == 0), only check stake
        if (gate.requiredItem == 0) {
            return meetsStake;
        }

        // If item required, apply AND/OR logic
        if (gate.requireBoth) {
            return meetsStake && hasItem;
        } else {
            return meetsStake || hasItem;
        }
    }

    /**
     * @notice Check if a user can purchase an item
     * @param user User address
     * @param id Item ID
     * @param amount Amount to purchase
     * @return canPurchase Whether purchase is valid
     * @return reason Reason if cannot purchase (0=can purchase, 1=inactive, 2=early, 3=late, 4=supply)
     */
    function checkPurchaseEligibility(address user, uint256 id, uint256 amount)
        external
        view
        returns (bool canPurchase, uint8 reason)
    {
        Item memory it = items[id];

        if (!it.active) return (false, 1);
        if (it.startTime != 0 && block.timestamp < it.startTime) return (false, 2);
        if (it.endTime != 0 && block.timestamp > it.endTime) return (false, 3);
        if (it.maxSupply != 0 && it.minted + amount > it.maxSupply) return (false, 4);

        return (true, 0);
    }

    /**
     * @notice Get purchase cost for an item
     * @param id Item ID
     * @param amount Amount to purchase
     * @return cost Total cost in app tokens
     */
    function getPurchaseCost(uint256 id, uint256 amount) external view returns (uint256 cost) {
        return items[id].price * amount;
    }

    /**
     * @notice Get remaining supply for an item
     * @param id Item ID
     * @return remaining Remaining supply (0 if unlimited)
     */
    function getRemainingSupply(uint256 id) external view returns (uint256 remaining) {
        Item memory it = items[id];
        if (it.maxSupply == 0) return type(uint256).max;
        return it.maxSupply > it.minted ? it.maxSupply - it.minted : 0;
    }

    /**
     * @notice Batch get items for efficient UI loading
     * @param ids Array of item IDs
     * @return itemList Array of items
     */
    function getItems(uint256[] calldata ids) external view returns (Item[] memory itemList) {
        itemList = new Item[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            itemList[i] = items[ids[i]];
        }
    }

    /**
     * @notice Batch get feature gates
     * @param featureIds Array of feature IDs
     * @return gateList Array of gates
     */
    function getFeatureGates(bytes32[] calldata featureIds)
        external
        view
        returns (FeatureGate[] memory gateList)
    {
        gateList = new FeatureGate[](featureIds.length);
        for (uint256 i = 0; i < featureIds.length; i++) {
            gateList[i] = gates[featureIds[i]];
        }
    }
}
