// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AppStakingVault
 * @author Elata Protocol
 * @notice Per-app staking vault for feature gating and governance
 * @dev Simple staking contract - apps read stakedOf(user) to gate features
 *
 * Key Features:
 * - Isolated per-app staking (clean, simple)
 * - No rewards logic (pure gating signal)
 * - View-only for app-side enforcement
 * - Future Snapshot weight for governance
 *
 * Usage:
 * 1. Users stake app tokens to unlock features
 * 2. Apps check stakedOf(user) >= threshold
 * 3. Users can unstake anytime (no lock period)
 */
contract AppStakingVault is Ownable, ReentrancyGuard {
    /// @notice App token being staked
    IERC20 public immutable APP;

    /// @notice Amount staked per user
    mapping(address => uint256) public stakedOf;

    /// @notice Total amount staked in vault
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount, uint256 newBalance);
    event Unstaked(address indexed user, uint256 amount, uint256 newBalance);

    error ZeroAmount();
    error InsufficientStake();

    /**
     * @notice Initialize staking vault
     * @param appToken Address of the app ERC20 token
     * @param owner_ Contract owner (app creator)
     */
    constructor(address appToken, address owner_) Ownable(owner_) {
        APP = IERC20(appToken);
    }

    /**
     * @notice Stake app tokens
     * @dev User must approve this contract first
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        APP.transferFrom(msg.sender, address(this), amount);
        stakedOf[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount, stakedOf[msg.sender]);
    }

    /**
     * @notice Unstake app tokens
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (stakedOf[msg.sender] < amount) revert InsufficientStake();

        stakedOf[msg.sender] -= amount;
        totalStaked -= amount;
        APP.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, stakedOf[msg.sender]);
    }
}

