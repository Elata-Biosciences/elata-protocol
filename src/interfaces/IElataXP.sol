// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IElataXP
 * @notice Interface for the ElataXP experience points token
 * @dev Used by bonding curves to check user XP for early access gating
 */
interface IElataXP {
    /**
     * @notice Get XP balance of an account
     * @param account Address to query
     * @return XP balance
     */
    function balanceOf(address account) external view returns (uint256);
}
