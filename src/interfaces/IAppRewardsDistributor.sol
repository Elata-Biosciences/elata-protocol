// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
     * @notice Distribute ELTA rewards across active vaults
     * @param amount Total ELTA to distribute
     */
    function distribute(uint256 amount) external;

    /**
     * @notice Claim rewards from a specific vault
     * @param vault Vault address
     * @param toEpoch Claim up to this epoch
     */
    function claim(address vault, uint256 toEpoch) external;
}
