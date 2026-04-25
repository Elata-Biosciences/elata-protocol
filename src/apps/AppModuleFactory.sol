// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppAccess1155} from "./AppAccess1155.sol";
import {IOwnable} from "./Interfaces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AppModuleFactory
 * @author Elata Protocol
 * @notice Factory for deploying AppAccess1155 (NFT items) for apps
 * @dev Restricted to app token owners only, optional ELTA creation fee
 *
 * Key Features:
 * - Deploys AppAccess1155 for NFT items and feature gates
 * - Restricted: only AppToken owner can deploy
 * - Optional ELTA fee to align protocol value
 * - Registry for discovery
 * - Non-upgradeable, simple
 *
 * Usage:
 * 1. App creator launches app via AppFactory (gets AppToken + AppStakingVault automatically)
 * 2. App creator calls deployModules() to add AppAccess1155 (pays ELTA fee if set)
 * 3. Configure items, gates, and launch
 *
 * Note: AppStakingVault is already deployed by AppFactory during app creation.
 * Note: EpochRewards removed - apps can use external airdrop services for rewards.
 */
contract AppModuleFactory is Ownable {
    /// @notice ELTA token address (address(0) to disable fees)
    address public immutable ELTA;

    /// @notice Protocol treasury for fee collection
    address public treasury;

    /// @notice Deployed AppAccess1155 by app token address
    mapping(address => address) public access1155ByApp;

    /// @notice ELTA fee for deploying modules
    uint256 public createFeeELTA;

    event ModuleDeployed(address indexed appToken, address access1155);
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);

    error NotTokenOwner();
    error ModuleAlreadyExists();

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

    /**
     * @notice Deploy AppAccess1155 for an app token
     * @dev Only callable by the AppToken owner
     * @dev AppStakingVault is already deployed by AppFactory during app creation
     * @param appToken AppToken address (must implement owner())
     * @param stakingVault AppStakingVault address (from AppFactory.apps[appId].vault)
     * @param baseURI Base URI for Access1155 metadata
     * @return access1155 Address of deployed AppAccess1155
     */
    function deployModules(address appToken, address stakingVault, string calldata baseURI)
        external
        returns (address access1155)
    {
        // Verify caller is token owner
        if (IOwnable(appToken).owner() != msg.sender) revert NotTokenOwner();

        // Prevent duplicate deployments
        if (access1155ByApp[appToken] != address(0)) revert ModuleAlreadyExists();

        // Collect ELTA fee if set
        if (createFeeELTA > 0 && ELTA != address(0)) IERC20(ELTA).transferFrom(msg.sender, treasury, createFeeELTA);

        // Deploy AppAccess1155 (msg.sender becomes owner)
        access1155 = address(new AppAccess1155(appToken, stakingVault, msg.sender, baseURI));

        // Register module
        access1155ByApp[appToken] = access1155;

        emit ModuleDeployed(appToken, access1155);
    }
}
