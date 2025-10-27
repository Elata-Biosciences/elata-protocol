// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAppFeeRouter
 * @notice Interface for the app fee routing system
 */
interface IAppFeeRouter {
    /**
     * @notice Collect fee from payer and forward to RewardsDistributor
     * @param payer Address paying the fee
     * @param grossAmount Gross trade amount for fee calculation
     */
    function takeAndForwardFee(address payer, uint256 grossAmount) external;

    /**
     * @notice Get current fee rate in basis points
     * @return Fee rate in basis points
     */
    function feeBps() external view returns (uint256);

    /**
     * @notice Calculate fee for a given amount
     * @param amount Amount to calculate fee for
     * @return fee Fee amount
     */
    function calculateFee(uint256 amount) external view returns (uint256 fee);
}
