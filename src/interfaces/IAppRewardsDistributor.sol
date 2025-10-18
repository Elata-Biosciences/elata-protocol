// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAppRewardsDistributor
 * @notice Interface for the app rewards distribution system
 */
interface IAppRewardsDistributor {
    /**
     * @notice Register a new app vault to receive rewards
     * @param vault Address of the AppStakingVault
     */
    function registerApp(address vault) external;

    /**
     * @notice Register a new app vault with token mapping
     * @param vault Address of the AppStakingVault
     * @param token Address of the app token
     */
    function registerApp(address vault, address token) external;

    /**
     * @notice Distribute ELTA rewards across active vaults
     * @param amount Total ELTA to distribute
     */
    function distribute(uint256 amount) external;

    /**
     * @notice Deposit app tokens as rewards for a specific app
     * @param token App token address
     * @param amount Amount of app tokens to distribute
     */
    function depositForApp(IERC20 token, uint256 amount) external;

    /**
     * @notice Claim rewards from a specific vault
     * @param vault Vault address
     * @param toEpoch Claim up to this epoch
     */
    function claim(address vault, uint256 toEpoch) external;

    /**
     * @notice Claim token rewards from a specific vault
     * @param vault Vault address
     * @param token Token to claim
     * @param toEpoch Claim up to this epoch
     */
    function claimToken(address vault, IERC20 token, uint256 toEpoch) external;
}
