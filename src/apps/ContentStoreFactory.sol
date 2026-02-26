// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ContentStore} from "./ContentStore.sol";
import {InAppContent721} from "./InAppContent721.sol";
import {IOwnable} from "./Interfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAppRegistry} from "../interfaces/IAppRegistry.sol";

/**
 * @title ContentStoreFactory
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Factory for deploying ContentStore sales contracts linked to InAppContent721 collections.
 * @dev Only the AppToken owner may deploy a ContentStore for their app. An optional ELTA fee can be
 *      configured. The deployed ContentStore is automatically granted minter rights on the target
 *      InAppContent721 contract. A registry tracks all deployed stores for discovery.
 */
contract ContentStoreFactory is Ownable {
    using SafeERC20 for IERC20;

    /// @notice ELTA token address (address(0) to disable fees)
    address public immutable ELTA;

    /// @notice USDC token address for ContentStore payments
    address public immutable USDC;

    /// @notice WETH used to wrap native payments in ContentStore
    address public immutable WETH;

    /// @notice Protocol treasury for fee collection
    address public treasury;

    /// @notice FeeSwapper address for 80/20 routing (set after deploy)
    address public feeSwapper;

    /// @notice ELTA fee for deploying content stores
    uint256 public createFeeELTA;

    /// @notice Deployed ContentStore by app token address
    mapping(address => address) public contentStoreByApp;

    /// @notice Deployed ContentStore by appId (tokenless-first)
    mapping(uint256 => address) public contentStoreByAppId;

    /// @notice AppRegistry for appId ownership + token attach validation
    IAppRegistry public immutable appRegistry;

    // =========== Events ===========

    event ContentStoreDeployed(address indexed appToken, address indexed contentStore, address indexed content721);
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);
    event FeeSwapperSet(address feeSwapper);

    // =========== Errors ===========

    error NotTokenOwner();
    error AlreadyDeployed();
    error NotContent721Owner();
    error ZeroAddress();
    error InvalidAppState();

    /**
     * @notice Initialize factory
     * @param elta ELTA token address (address(0) to disable fees)
     * @param usdc USDC token address
     * @param weth WETH token address (for native payment wrapping)
     * @param initialOwner Factory owner
     * @param treasury_ Protocol treasury address
     * @param feeSwapper_ FeeSwapper address (can be address(0) initially; set later)
     */
    constructor(
        address elta,
        address usdc,
        address weth,
        address appRegistry_,
        address initialOwner,
        address treasury_,
        address feeSwapper_
    ) Ownable(initialOwner) {
        if (weth == address(0)) revert ZeroAddress();
        if (appRegistry_ == address(0)) revert ZeroAddress();
        ELTA = elta;
        USDC = usdc;
        WETH = weth;
        appRegistry = IAppRegistry(appRegistry_);
        treasury = treasury_;
        feeSwapper = feeSwapper_;
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
     * @notice Set FeeSwapper address (routing sink)
     * @dev Can be set post-deploy once FeeSwapper exists.
     */
    function setFeeSwapper(address fs) external onlyOwner {
        feeSwapper = fs;
        emit FeeSwapperSet(fs);
    }

    /**
     * @notice Set ELTA creation fee
     * @param fee New fee amount in ELTA
     */
    function setCreateFee(uint256 fee) external onlyOwner {
        createFeeELTA = fee;
        emit FeeSet(fee);
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
            weth: WETH,
            content721: content721,
            appRegistry: address(appRegistry),
            factory: address(this),
            admin: msg.sender,
            feeSwapper: feeSwapper
        });

        contentStore = address(new ContentStore(config));

        // Note: Caller must manually call content721.setMinter(contentStore) after deployment
        // The factory cannot do this as it's not the owner of the content721 contract

        // Register deployment
        contentStoreByApp[appToken] = contentStore;
        contentStoreByAppId[appId] = contentStore;

        emit ContentStoreDeployed(appToken, contentStore, content721);
    }

    /**
     * @notice Deploy ContentStore for an appId before token launch (tokenless mode).
     * @dev Only callable by the app ownerSafe (from AppRegistry).
     */
    function deployContentStoreForApp(uint256 appId, address content721) external returns (address contentStore) {
        IAppRegistry.AppInfo memory info = appRegistry.getApp(appId);
        address ownerSafe = info.ownerSafe;
        if (ownerSafe == address(0)) revert InvalidAppState();
        if (msg.sender != ownerSafe) revert NotTokenOwner();

        // Verify caller owns the content721 (ownerSafe must be owner)
        if (content721 == address(0) || IOwnable(content721).owner() != ownerSafe) revert NotContent721Owner();

        if (contentStoreByAppId[appId] != address(0)) revert AlreadyDeployed();

        _collectFee();

        ContentStore.InitConfig memory config = ContentStore.InitConfig({
            appId: appId,
            appToken: address(0),
            elta: ELTA,
            usdc: USDC,
            weth: WETH,
            content721: content721,
            appRegistry: address(appRegistry),
            factory: address(this),
            admin: ownerSafe,
            feeSwapper: feeSwapper
        });

        contentStore = address(new ContentStore(config));
        contentStoreByAppId[appId] = contentStore;

        emit ContentStoreDeployed(address(0), contentStore, content721);
    }

    /**
     * @notice Attach a launched app token to an existing tokenless ContentStore and register it under appToken.
     * @dev Only callable by the app ownerSafe (from AppRegistry).
     */
    function attachLaunchedToken(uint256 appId) external {
        IAppRegistry.AppInfo memory info = appRegistry.getApp(appId);
        address ownerSafe = info.ownerSafe;
        if (ownerSafe == address(0)) revert InvalidAppState();
        if (msg.sender != ownerSafe) revert NotTokenOwner();
        if (!info.tokenLaunched || info.appToken == address(0)) revert InvalidAppState();

        address store = contentStoreByAppId[appId];
        if (store == address(0)) revert InvalidAppState();

        // Register by appToken for discoverability.
        if (contentStoreByApp[info.appToken] == address(0)) {
            contentStoreByApp[info.appToken] = store;
        }

        // Enable APP payments in the store.
        ContentStore(payable(store)).setAppToken(info.appToken);
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

    function getContentStoreByAppId(uint256 appId) external view returns (address contentStore) {
        return contentStoreByAppId[appId];
    }
}
