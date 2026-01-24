// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "./InAppContent721.sol";
import {ContentStore} from "./ContentStore.sol";
import {IOwnable} from "./Interfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AppModuleFactory
 * @author Elata Protocol
 * @notice Factory for deploying InAppContent721 and ContentStore for apps
 * @dev Restricted to app token owners only, optional ELTA creation fee
 *
 * Key Features:
 * - Deploys InAppContent721 (ERC-721) for digital content/collectibles
 * - Deploys ContentStore for primary sales with time windows and feature gates
 * - Restricted: only AppToken owner can deploy
 * - Optional ELTA fee to align protocol value
 * - Registry for discovery
 * - Non-upgradeable, simple
 *
 * Usage:
 * 1. App creator launches app via AppFactory (gets AppToken + AppStakingVault automatically)
 * 2. App creator calls deployModules() to add InAppContent721 + ContentStore (pays ELTA fee if set)
 * 3. Configure content listings, time windows, and feature gates
 *
 * Note: AppStakingVault is already deployed by AppFactory during app creation.
 */
contract AppModuleFactory is Ownable {
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

    /// @notice Deployed InAppContent721 by app token address
    mapping(address => address) public content721ByApp;

    /// @notice Deployed ContentStore by app token address
    mapping(address => address) public contentStoreByApp;

    /// @notice ELTA fee for deploying modules
    uint256 public createFeeELTA;

    event ModulesDeployed(address indexed appToken, address content721, address contentStore);
    event TreasurySet(address treasury);
    event FeeCollectorSet(address feeCollector);
    event FeeSet(uint256 fee);
    event DefaultProtocolFeeBpsSet(uint256 bps);

    error NotTokenOwner();
    error ModuleAlreadyExists();
    error InvalidProtocolFeeBps();

    /// @notice Maximum protocol fee (15%)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 1500;

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

    /**
     * @notice Deploy InAppContent721 and ContentStore for an app token
     * @dev Only callable by the AppToken owner
     * @param appId App ID for fee routing
     * @param appToken AppToken address (must implement owner())
     * @param name Collection name for InAppContent721
     * @param symbol Collection symbol for InAppContent721
     * @param contractURI Contract-level metadata URI for InAppContent721
     * @return content721 Address of deployed InAppContent721
     * @return contentStore Address of deployed ContentStore
     */
    function deployModules(
        uint256 appId,
        address appToken,
        string calldata name,
        string calldata symbol,
        string calldata contractURI
    ) external returns (address content721, address contentStore) {
        // Verify caller is token owner
        if (IOwnable(appToken).owner() != msg.sender) revert NotTokenOwner();

        // Prevent duplicate deployments
        if (content721ByApp[appToken] != address(0)) revert ModuleAlreadyExists();

        // Collect ELTA fee if set
        _collectFee();

        // Deploy InAppContent721 (minter set to address(0) temporarily)
        content721 = _deployContent721(appId, name, symbol, contractURI);

        // Deploy ContentStore
        contentStore = _deployContentStore(appId, appToken, content721);

        // Set ContentStore as the minter for InAppContent721
        InAppContent721(content721).setMinter(contentStore);

        // Register modules
        content721ByApp[appToken] = content721;
        contentStoreByApp[appToken] = contentStore;

        emit ModulesDeployed(appToken, content721, contentStore);
    }

    /**
     * @dev Internal function to collect ELTA fee
     */
    function _collectFee() internal {
        if (createFeeELTA > 0 && ELTA != address(0)) {
            IERC20(ELTA).safeTransferFrom(msg.sender, treasury, createFeeELTA);
        }
    }

    /**
     * @dev Internal function to deploy InAppContent721
     */
    function _deployContent721(
        uint256 appId,
        string calldata name,
        string calldata symbol,
        string calldata contractURI
    ) internal returns (address) {
        return address(new InAppContent721(appId, name, symbol, msg.sender, address(0), contractURI));
    }

    /**
     * @dev Internal function to deploy ContentStore
     */
    function _deployContentStore(uint256 appId, address appToken, address content721) internal returns (address) {
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
        return address(new ContentStore(config));
    }

    /**
     * @notice Get deployed modules for an app
     * @param appToken App token address
     * @return content721 InAppContent721 address (address(0) if not deployed)
     * @return contentStore ContentStore address (address(0) if not deployed)
     */
    function getModules(address appToken) external view returns (address content721, address contentStore) {
        return (content721ByApp[appToken], contentStoreByApp[appToken]);
    }
}
