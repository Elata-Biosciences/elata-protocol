// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ITreasuryUSDCVault
 * @notice Interface for the TreasuryUSDCVault contract
 * @dev Used by FeeManager to deposit USDC revenue
 */
interface ITreasuryUSDCVault {
    /**
     * @notice Deposit USDC revenue from fee settlement
     * @dev Only callable by FeeManager during daily settlement
     * @param appId The app ID this revenue is attributed to
     * @param amount Amount of USDC to deposit
     * @param epochId The epoch this settlement is for
     */
    function deposit(uint256 appId, uint256 amount, uint256 epochId) external;

    /**
     * @notice Get current USDC balance
     * @return Current USDC balance in vault
     */
    function balance() external view returns (uint256);

    /**
     * @notice Total USDC revenue ever received
     * @return Total revenue amount
     */
    function totalRevenue() external view returns (uint256);

    /**
     * @notice Revenue received per app
     * @param appId App ID to query
     * @return Revenue for that app
     */
    function revenueByApp(uint256 appId) external view returns (uint256);

    /**
     * @notice Revenue received per epoch
     * @param epochId Epoch ID to query
     * @return Revenue for that epoch
     */
    function revenueByEpoch(uint256 epochId) external view returns (uint256);
}
