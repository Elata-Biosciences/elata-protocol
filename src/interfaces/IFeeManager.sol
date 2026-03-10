// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IFeeManager
 * @notice Interface for the FeeManager contract
 * @dev Used by RewardsDistributor to deposit treasury fees for USDC conversion
 */
interface IFeeManager {
    /**
     * @notice Deposit ELTA fees for a specific app
     * @dev Only callable by authorized depositors
     * @param appId The app ID to credit (use 0 for protocol-wide fees)
     * @param amount Amount of ELTA to deposit
     */
    function depositEltaForApp(uint256 appId, uint256 amount) external;

    /**
     * @notice Close the epoch for an app and distribute fees
     * @dev Permissionless - anyone can call to earn incentive
     * @param appId The app ID to close epoch for
     */
    function closeEpoch(uint256 appId) external;

    /**
     * @notice Get pending ELTA to distribute for an app
     * @param appId The app ID
     * @return Amount of pending ELTA
     */
    function pendingEltaToDistribute(uint256 appId) external view returns (uint256);

    /**
     * @notice Get last epoch close timestamp for an app
     * @param appId The app ID
     * @return Timestamp of last epoch close
     */
    function lastEpochClose(uint256 appId) external view returns (uint256);

    /**
     * @notice Get the current epoch ID
     * @return Current epoch number
     */
    function getCurrentEpochId() external view returns (uint256);

    /**
     * @notice Check if an address is an authorized depositor
     * @param depositor Address to check
     * @return Whether the address can deposit
     */
    function isDepositor(address depositor) external view returns (bool);
}
