// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRewardsDistributor
 * @notice Interface for the main rewards distribution system
 */
interface IRewardsDistributor {
    /**
     * @notice Deposit ELTA revenues and split 70/15/15
     * @param amount Total ELTA to deposit and split
     */
    function deposit(uint256 amount) external;
}
