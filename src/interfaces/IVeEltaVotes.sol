// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVeEltaVotes
 * @notice Interface for veELTA voting power queries
 */
interface IVeEltaVotes {
    /**
     * @notice Get past voting power for an account at a specific block
     * @param account Address to check
     * @param blockNumber Block number to query
     * @return Voting power at that block
     */
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Get total voting power at a specific block
     * @param blockNumber Block number to query
     * @return Total voting power at that block
     */
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Get current balance of veELTA tokens
     * @param account Address to check
     * @return Current veELTA balance
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Get current total supply of veELTA
     * @return Current total supply
     */
    function totalSupply() external view returns (uint256);
}
