// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStakeVaultVotes
 * @notice Interface for app staking vault snapshot queries
 */
interface IStakeVaultVotes {
    /**
     * @notice Get total staked amount (vault token supply)
     * @return Total stake-share tokens in circulation
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Get past voting power (staked balance) for an account at a specific block
     * @param account Address to check
     * @param blockNumber Block number to query
     * @return Staked balance at that block
     */
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Get current staked balance
     * @param account Address to check
     * @return Current staked balance
     */
    function balanceOf(address account) external view returns (uint256);
}
