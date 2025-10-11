// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOwnable } from "./Interfaces.sol";
import { AppAccess1155 } from "./AppAccess1155.sol";
import { AppStakingVault } from "./AppStakingVault.sol";
import { EpochRewards } from "./EpochRewards.sol";

/**
 * @title AppModuleFactory
 * @author Elata Protocol
 * @notice Factory for deploying app utility modules with ELTA fee support
 * @dev Restricted to app token owners only, optional ELTA creation fee
 *
 * Key Features:
 * - Deploys Access1155 + StakingVault pair per app
 * - Restricted: only AppToken owner can deploy
 * - Optional ELTA fee to align protocol value
 * - Registry for discovery
 * - Non-upgradeable, simple
 *
 * Usage:
 * 1. App creator deploys AppToken
 * 2. App creator calls deployModules() (pays ELTA fee if set)
 * 3. Receives configured Access1155 + StakingVault
 * 4. Configure items, gates, and launch
 */
contract AppModuleFactory is Ownable {
    /// @notice ELTA token address (address(0) to disable fees)
    address public immutable ELTA;

    /// @notice Protocol treasury for fee collection
    address public treasury;

    struct Modules {
        address access1155; // AppAccess1155 instance
        address stakingVault; // AppStakingVault instance
        address epochRewards; // EpochRewards instance
    }

    /// @notice Deployed modules by app token address
    mapping(address => Modules) public modulesByApp;

    /// @notice ELTA fee for deploying modules
    uint256 public createFeeELTA;

    event ModulesDeployed(
        address indexed appToken, address access1155, address stakingVault, address epochRewards
    );
    event TreasurySet(address treasury);
    event FeeSet(uint256 fee);

    error NotTokenOwner();
    error ModulesAlreadyExist();

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
     * @notice Deploy utility modules for an app token
     * @dev Only callable by the AppToken owner
     * @param appToken AppToken address (must implement owner())
     * @param baseURI Base URI for Access1155 metadata
     * @return access1155 Address of deployed AppAccess1155
     * @return staking Address of deployed AppStakingVault
     * @return epochs Address of deployed EpochRewards
     */
    function deployModules(address appToken, string calldata baseURI)
        external
        returns (address access1155, address staking, address epochs)
    {
        // Verify caller is token owner
        if (IOwnable(appToken).owner() != msg.sender) {
            revert NotTokenOwner();
        }

        // Prevent duplicate deployments
        if (modulesByApp[appToken].access1155 != address(0)) {
            revert ModulesAlreadyExist();
        }

        // Collect ELTA fee if set
        if (createFeeELTA > 0 && ELTA != address(0)) {
            IERC20(ELTA).transferFrom(msg.sender, treasury, createFeeELTA);
        }

        // Deploy modules (msg.sender becomes owner of all)
        staking = address(new AppStakingVault(appToken, msg.sender));
        access1155 = address(new AppAccess1155(appToken, staking, msg.sender, baseURI));
        epochs = address(new EpochRewards(appToken, msg.sender));

        // Register modules
        modulesByApp[appToken] = Modules(access1155, staking, epochs);

        emit ModulesDeployed(appToken, access1155, staking, epochs);
    }
}
