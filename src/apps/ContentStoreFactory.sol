// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ContentStore} from "./ContentStore.sol";
import {InAppContent721} from "./InAppContent721.sol";
import {IOwnable} from "./Interfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ContentStoreFactory
 * @author Elata Protocol
 * @notice Factory for deploying ContentStore sales contracts for apps
 * @dev Restricted to app token owners only, optional ELTA creation fee
 *
 * Key Features:
 * - Deploys ContentStore for primary sales with time windows and feature gates
 * - Links to existing InAppContent721 for minting
 * - Restricted: only AppToken owner can deploy
 * - Optional ELTA fee to align protocol value
 * - Registry for discovery
 * - Non-upgradeable, simple
 *
 * Usage:
 * 1. App creator deploys InAppContent721 via InAppContent721Factory
 * 2. App creator calls deployContentStore() to add sales functionality
 * 3. ContentStore is automatically set as minter for the InAppContent721
 * 4. Configure content listings, time windows, and feature gates
 */
contract ContentStoreFactory is Ownable {
    using SafeERC20 for IERC20;

    /// @notice ELTA token address (address(0) to disable fees)
    address public immutable ELTA;

    /// @notice USDC token address for ContentStore payments
    address public immutable USDC;

    /// @notice Protocol treasury for fee collection
    address public treasury;

    /// @notice FeeCollector address for ContentStore integration
    address public feeCollector;

    /// @notice Default protocol fee for ContentStore (in bps, e.g., 500 = 5%)
    uint256 public defaultProtocolFeeBps;

    /// @notice ELTA fee for deploying content stores
    uint256 public createFeeELTA;

    /// @notice Deployed ContentStore by app token address
    mapping(address => address) public contentStoreByApp;

    /// @notice Maximum protocol fee (15%)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1500;

    // =========== Events ===========

    event ContentStoreDeployed(address indexed appToken, address indexed contentStore, address indexed content721);
    event TreasurySet(address treasury);
    event FeeCollectorSet(address feeCollector);
    event FeeSet(uint256 fee);
    event DefaultProtocolFeeBpsSet(uint256 bps);

    // =========== Errors ===========

    error NotTokenOwner();
    error AlreadyDeployed();
    error InvalidProtocolFeeBps();
    error NotContent721Owner();

    /**
     * @notice Initialize factory
     * @param elta ELTA token address (address(0) to disable fees)
     * @param usdc USDC token address
     * @param initialOwner Factory owner
     * @param treasury_ Protocol treasury address
     * @param feeCollector_ FeeCollector address
     * @param defaultProtocolFeeBps_ Default protocol fee for new ContentStores
     */
    constructor(
        address elta,
        address usdc,
        address initialOwner,
        address treasury_,
        address feeCollector_,
        uint256 defaultProtocolFeeBps_
    ) Ownable(initialOwner) {
        if (defaultProtocolFeeBps_ > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();
        ELTA = elta;
        USDC = usdc;
        treasury = treasury_;
        feeCollector = feeCollector_;
        defaultProtocolFeeBps = defaultProtocolFeeBps_;
    }

    // =========== Admin Functions ===========

    /**
     * @notice Set protocol treasury address
     * @param t New treasury address
     */
    function setTreasury(address t) external onlyOwner {
        treasury = t;
        emit TreasurySet(t);
    }

    /**
     * @notice Set fee collector address
     * @param fc New fee collector address
     */
    function setFeeCollector(address fc) external onlyOwner {
        feeCollector = fc;
        emit FeeCollectorSet(fc);
    }

    /**
     * @notice Set ELTA creation fee
     * @param fee New fee amount in ELTA
     */
    function setCreateFee(uint256 fee) external onlyOwner {
        createFeeELTA = fee;
        emit FeeSet(fee);
    }

    /**
     * @notice Set default protocol fee for new ContentStores
     * @param bps New fee in basis points (max 1500 = 15%)
     */
    function setDefaultProtocolFeeBps(uint256 bps) external onlyOwner {
        if (bps > MAX_PROTOCOL_FEE_BPS) revert InvalidProtocolFeeBps();
        defaultProtocolFeeBps = bps;
        emit DefaultProtocolFeeBpsSet(bps);
    }

    // =========== Deployment Function ===========

    /**
     * @notice Deploy ContentStore for an app token
     * @dev Only callable by the AppToken owner. Caller must also own the InAppContent721.
     *      ContentStore is automatically set as the minter for InAppContent721.
     * @param appId App ID for fee routing
     * @param appToken AppToken address (must implement owner())
     * @param content721 InAppContent721 address to link (caller must be owner)
     * @return contentStore Address of deployed ContentStore
     */
    function deployContentStore(uint256 appId, address appToken, address content721)
        external
        returns (address contentStore)
    {
        // Verify caller is token owner
        if (IOwnable(appToken).owner() != msg.sender) revert NotTokenOwner();

        // Verify caller owns the content721
        if (content721 != address(0) && IOwnable(content721).owner() != msg.sender) {
            revert NotContent721Owner();
        }

        // Prevent duplicate deployments
        if (contentStoreByApp[appToken] != address(0)) revert AlreadyDeployed();

        // Collect ELTA fee if set
        _collectFee();

        // Deploy ContentStore with app creator as admin
        ContentStore.InitConfig memory config = ContentStore.InitConfig({
            appId: appId,
            appToken: appToken,
            elta: ELTA,
            usdc: USDC,
            treasury: treasury,
            content721: content721,
            admin: msg.sender,
            feeCollector: feeCollector,
            protocolFeeBps: defaultProtocolFeeBps
        });

        contentStore = address(new ContentStore(config));

        // If content721 is provided, set ContentStore as minter
        if (content721 != address(0)) {
            InAppContent721(content721).setMinter(contentStore);
        }

        // Register deployment
        contentStoreByApp[appToken] = contentStore;

        emit ContentStoreDeployed(appToken, contentStore, content721);
    }

    // =========== Internal Functions ===========

    /**
     * @dev Internal function to collect ELTA fee
     */
    function _collectFee() internal {
        if (createFeeELTA > 0 && ELTA != address(0)) {
            IERC20(ELTA).safeTransferFrom(msg.sender, treasury, createFeeELTA);
        }
    }

    // =========== View Functions ===========

    /**
     * @notice Get deployed content store for an app
     * @param appToken App token address
     * @return contentStore ContentStore address (address(0) if not deployed)
     */
    function getContentStore(address appToken) external view returns (address contentStore) {
        return contentStoreByApp[appToken];
    }
}
