// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IElataPoints
 * @notice Interface for the ElataPoints experience points token
 * @dev Used by bonding curves to check user Points for early access gating
 */
interface IElataPoints {
    /**
     * @notice Get Points balance of an account
     * @param account Address to query
     * @return Points balance
     */
    function balanceOf(address account) external view returns (uint256);
}
