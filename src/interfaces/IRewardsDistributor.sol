// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    /**
     * @notice Deposit arbitrary ERC20 tokens as veELTA rewards
     * @param token Token address
     * @param amount Amount to deposit
     */
    function depositVeInToken(IERC20 token, uint256 amount) external;
}
