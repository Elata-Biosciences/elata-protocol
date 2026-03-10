// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "./InAppContent721.sol";
import {IOwnable} from "./Interfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAppRegistry} from "../interfaces/IAppRegistry.sol";

/**
 * @title InAppContent721Factory
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Factory for deploying InAppContent721 (ERC-721) collections for apps.
 * @dev Only the AppToken owner may deploy a collection for their app. An optional ELTA creation fee
 *      can be configured. A registry tracks all deployed collections for discovery. Creators may
 *      subsequently deploy a ContentStore via ContentStoreFactory to enable primary sales.
 */
contract InAppContent721Factory is Ownable {
    using SafeERC20 for IERC20;

    /// @notice ELTA token address (address(0) to disable fees)
    address public immutable ELTA;

    /// @notice Protocol treasury for fee collection
    address public treasury;

    /// @notice ELTA fee for deploying content collections
    uint256 public createFeeELTA;

    /// @notice Deployed InAppContent721 by app token address
    mapping(address => address) public content721ByApp;

    /// @notice Deployed InAppContent721 by appId (tokenless-first)
    mapping(uint256 => address) public content721ByAppId;

    /// @notice AppRegistry for appId ownership + token attach validation
    IAppRegistry public immutable appRegistry;

    // =========== Events ===========

    event Content721Deployed(address indexed appToken, address indexed content721, uint256 appId);
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);

    // =========== Errors ===========

    error NotTokenOwner();
    error AlreadyDeployed();
    error ZeroAddress();
    error InvalidAppState();

    /**
     * @notice Initialize factory
     * @param elta ELTA token address (address(0) to disable fees)
     * @param initialOwner Factory owner
     * @param treasury_ Protocol treasury address
     */
    constructor(address elta, address appRegistry_, address initialOwner, address treasury_) Ownable(initialOwner) {
        if (appRegistry_ == address(0)) revert ZeroAddress();
        ELTA = elta;
        appRegistry = IAppRegistry(appRegistry_);
        treasury = treasury_;
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
     * @notice Set ELTA creation fee
     * @param fee New fee amount in ELTA
     */
    function setCreateFee(uint256 fee) external onlyOwner {
        createFeeELTA = fee;
        emit FeeSet(fee);
    }

    // =========== Deployment Function ===========

    /**
     * @notice Deploy InAppContent721 for an app token
     * @dev Only callable by the AppToken owner
     * @param appId App ID for attribution
     * @param appToken AppToken address (must implement owner())
     * @param name Collection name for InAppContent721
     * @param symbol Collection symbol for InAppContent721
     * @param contractURI Contract-level metadata URI for InAppContent721
     * @return content721 Address of deployed InAppContent721
     */
    function deployContent721(
        uint256 appId,
        address appToken,
        string calldata name,
        string calldata symbol,
        string calldata contractURI
    ) external returns (address content721) {
        // Verify caller is token owner
        if (IOwnable(appToken).owner() != msg.sender) revert NotTokenOwner();

        // Prevent duplicate deployments
        if (content721ByApp[appToken] != address(0)) revert AlreadyDeployed();

        // Collect ELTA fee if set
        _collectFee();

        // Deploy InAppContent721 with caller as owner
        // Minter will be set later by owner (typically to ContentStore)
        content721 = address(new InAppContent721(appId, name, symbol, msg.sender, address(0), contractURI));

        // Register deployment
        content721ByApp[appToken] = content721;
        content721ByAppId[appId] = content721;

        emit Content721Deployed(appToken, content721, appId);
    }

    /**
     * @notice Deploy InAppContent721 for an appId before token launch (tokenless mode).
     * @dev Only callable by the app ownerSafe (from AppRegistry).
     */
    function deployContent721ForApp(
        uint256 appId,
        string calldata name,
        string calldata symbol,
        string calldata contractURI
    ) external returns (address content721) {
        IAppRegistry.AppInfo memory info = appRegistry.getApp(appId);
        address ownerSafe = info.ownerSafe;
        if (ownerSafe == address(0)) revert InvalidAppState();
        if (msg.sender != ownerSafe) revert NotTokenOwner();

        if (content721ByAppId[appId] != address(0)) revert AlreadyDeployed();

        _collectFee();

        // Owner is the app ownerSafe; minter will be set later (typically to ContentStore).
        content721 = address(new InAppContent721(appId, name, symbol, ownerSafe, address(0), contractURI));
        content721ByAppId[appId] = content721;

        emit Content721Deployed(address(0), content721, appId);
    }

    /**
     * @notice Attach the launched app token to an existing tokenless content721 and register it under appToken.
     * @dev Only callable by the app ownerSafe (from AppRegistry).
     */
    function attachLaunchedToken(uint256 appId) external {
        IAppRegistry.AppInfo memory info = appRegistry.getApp(appId);
        address ownerSafe = info.ownerSafe;
        if (ownerSafe == address(0)) revert InvalidAppState();
        if (msg.sender != ownerSafe) revert NotTokenOwner();
        if (!info.tokenLaunched || info.appToken == address(0)) revert InvalidAppState();

        address content721 = content721ByAppId[appId];
        if (content721 == address(0)) revert InvalidAppState();

        if (content721ByApp[info.appToken] == address(0)) {
            content721ByApp[info.appToken] = content721;
        }
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
     * @notice Get deployed content721 for an app
     * @param appToken App token address
     * @return content721 InAppContent721 address (address(0) if not deployed)
     */
    function getContent721(address appToken) external view returns (address content721) {
        return content721ByApp[appToken];
    }

    function getContent721ByAppId(uint256 appId) external view returns (address content721) {
        return content721ByAppId[appId];
    }
}
