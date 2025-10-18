// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IUniswapV2Pair } from "../interfaces/IUniswapV2Pair.sol";

/**
 * @title LpLocker
 * @author Elata Biosciences
 * @notice Time-locked LP token holder for app token liquidity
 * @dev Non-custodial LP locker with fixed unlock time
 *
 * Features:
 * - Immutable lock parameters for security
 * - Single claim after unlock time
 * - Non-custodial design
 * - Emergency-resistant (no early unlock)
 */
contract LpLocker {
    address public immutable lpToken;
    address public immutable beneficiary;
    uint256 public immutable unlockAt;
    uint256 public immutable appId;

    bool public claimed;

    event LpLocked(
        uint256 indexed appId,
        address lpToken,
        address beneficiary,
        uint256 unlockAt,
        uint256 amount
    );
    event LpClaimed(uint256 indexed appId, address beneficiary, uint256 amount);

    error NotYetUnlocked();
    error Unauthorized();
    error AlreadyClaimed();
    error TransferFailed();

    /**
     * @notice Initialize LP locker
     * @param _appId App ID for tracking
     * @param _lpToken LP token address to lock
     * @param _beneficiary Address that can claim after unlock
     * @param _unlockAt Timestamp when LP can be claimed
     */
    constructor(uint256 _appId, address _lpToken, address _beneficiary, uint256 _unlockAt) {
        require(_lpToken != address(0), "Zero LP token");
        require(_beneficiary != address(0), "Zero beneficiary");
        require(_unlockAt > block.timestamp, "Invalid unlock time");

        appId = _appId;
        lpToken = _lpToken;
        beneficiary = _beneficiary;
        unlockAt = _unlockAt;
    }

    /**
     * @notice Lock LP tokens in this contract
     * @param amount Amount of LP tokens to lock
     */
    function lockLp(uint256 amount) external {
        require(amount > 0, "Zero amount");

        bool success = IUniswapV2Pair(lpToken).transfer(address(this), amount);
        if (!success) revert TransferFailed();

        emit LpLocked(appId, lpToken, beneficiary, unlockAt, amount);
    }

    /**
     * @notice Claim locked LP tokens after unlock time
     */
    function claim() external {
        if (block.timestamp < unlockAt) revert NotYetUnlocked();
        if (msg.sender != beneficiary) revert Unauthorized();
        if (claimed) revert AlreadyClaimed();

        claimed = true;

        uint256 balance = IUniswapV2Pair(lpToken).balanceOf(address(this));
        require(balance > 0, "No LP tokens to claim");

        bool success = IUniswapV2Pair(lpToken).transfer(beneficiary, balance);
        if (!success) revert TransferFailed();

        emit LpClaimed(appId, beneficiary, balance);
    }

    /**
     * @notice Get locked LP token balance
     * @return Current LP token balance in this contract
     */
    function getLockedBalance() external view returns (uint256) {
        return IUniswapV2Pair(lpToken).balanceOf(address(this));
    }

    /**
     * @notice Check if LP tokens can be claimed
     * @return Whether unlock time has passed and tokens haven't been claimed
     */
    function canClaim() external view returns (bool) {
        return block.timestamp >= unlockAt && !claimed;
    }

    /**
     * @notice Get time remaining until unlock
     * @return Seconds until unlock (0 if already unlocked)
     */
    function timeUntilUnlock() external view returns (uint256) {
        if (block.timestamp >= unlockAt) return 0;
        return unlockAt - block.timestamp;
    }
}
