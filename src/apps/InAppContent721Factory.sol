// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {InAppContent721} from "./InAppContent721.sol";
import {IOwnable} from "./Interfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title InAppContent721Factory
 * @author Elata Protocol
 * @notice Factory for deploying InAppContent721 (ERC-721) collections for apps
 * @dev Restricted to app token owners only, optional ELTA creation fee
 *
 * Key Features:
 * - Deploys InAppContent721 (ERC-721) for digital content/collectibles
 * - Restricted: only AppToken owner can deploy
 * - Optional ELTA fee to align protocol value
 * - Registry for discovery
 * - Non-upgradeable, simple
 *
 * Usage:
 * 1. App creator launches app via AppFactory (gets AppToken + AppStakingVault automatically)
 * 2. App creator calls deployContent721() to add InAppContent721 (pays ELTA fee if set)
 * 3. Optionally deploy ContentStore via ContentStoreFactory to enable sales
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

    // =========== Events ===========

    event Content721Deployed(address indexed appToken, address indexed content721, uint256 appId);
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);

    // =========== Errors ===========

    error NotTokenOwner();
    error AlreadyDeployed();

    /**
     * @notice Initialize factory
     * @param elta ELTA token address (address(0) to disable fees)
     * @param initialOwner Factory owner
     * @param treasury_ Protocol treasury address
     */
    constructor(address elta, address initialOwner, address treasury_) Ownable(initialOwner) {
        ELTA = elta;
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

        emit Content721Deployed(appToken, content721, appId);
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
}
