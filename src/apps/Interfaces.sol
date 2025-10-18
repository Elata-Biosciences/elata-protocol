// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAppToken
 * @notice Interface for app token burn functionality
 */
interface IAppToken {
    /**
     * @notice Burns tokens from a specified account
     * @param account Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @notice Returns the number of decimals used by the token
     * @return Number of decimals
     */
    function decimals() external view returns (uint8);
}

/**
 * @title IOwnable
 * @notice Interface for ownership queries
 */
interface IOwnable {
    /**
     * @notice Returns the owner of the contract
     * @return Address of the owner
     */
    function owner() external view returns (address);
}
