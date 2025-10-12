// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title AppStakingVault
 * @author Elata Protocol
 * @notice Per-app staking vault with snapshot-enabled ERC20Votes shares
 * @dev Non-transferable stake-share tokens for feature gating and rewards
 *
 * Architecture:
 * - Users stake app tokens, receive non-transferable share tokens 1:1
 * - Share balance = voting power for app governance
 * - Snapshot at each block enables on-chain reward distribution
 * - Apps read balanceOf(user) for feature gating
 * - AppRewardsDistributor uses getPastVotes() for pro-rata rewards
 *
 * Usage:
 * 1. Users stake app tokens to unlock features
 * 2. Apps check balanceOf(user) >= threshold
 * 3. Users earn ELTA rewards proportional to stake
 * 4. Users can unstake anytime (no lock period)
 */
contract AppStakingVault is ERC20, ERC20Permit, ERC20Votes, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Insufficient();

    /// @notice App token being staked
    IERC20 public immutable APP;

    event Staked(address indexed user, uint256 amount, uint256 newBalance);
    event Unstaked(address indexed user, uint256 amount, uint256 newBalance);
    event StakedFor(address indexed beneficiary, uint256 amount, address indexed staker);

    /**
     * @notice Initialize staking vault
     * @param appName App name (e.g., "NeuroGame")
     * @param appSymbol App symbol (e.g., "NGT")
     * @param appToken Address of the app ERC20 token
     * @param owner_ Contract owner (app creator or factory)
     */
    constructor(string memory appName, string memory appSymbol, IERC20 appToken, address owner_)
        ERC20(string.concat("Staked ", appName), string.concat("s", appSymbol))
        ERC20Permit(string.concat("Staked ", appName))
        Ownable(owner_)
    {
        if (address(appToken) == address(0)) revert Errors.ZeroAddress();
        APP = appToken;
    }

    /**
     * @notice Stake app tokens
     * @dev User must approve this contract first
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();

        APP.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        // Auto-delegate to self for voting power (ERC20Votes requirement)
        if (delegates(msg.sender) == address(0)) {
            _delegate(msg.sender, msg.sender);
        }

        emit Staked(msg.sender, amount, balanceOf(msg.sender));
    }

    /**
     * @notice Stake on behalf of another address
     * @dev Used by factory for auto-staking creator share at launch
     * @param beneficiary Address to receive stake-shares
     * @param amount Amount of tokens to stake
     */
    function stakeFor(address beneficiary, uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();
        if (beneficiary == address(0)) revert Errors.ZeroAddress();

        APP.safeTransferFrom(msg.sender, address(this), amount);
        _mint(beneficiary, amount);

        // Auto-delegate to self for voting power (ERC20Votes requirement)
        if (delegates(beneficiary) == address(0)) {
            _delegate(beneficiary, beneficiary);
        }

        emit StakedFor(beneficiary, amount, msg.sender);
    }

    /**
     * @notice Unstake app tokens
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();
        if (balanceOf(msg.sender) < amount) revert Insufficient();

        _burn(msg.sender, amount);
        APP.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, balanceOf(msg.sender));
    }

    /**
     * @notice Get user's staked balance
     * @dev Convenience function, equivalent to balanceOf()
     * @param user User address
     * @return Staked balance
     */
    function stakedOf(address user) external view returns (uint256) {
        return balanceOf(user);
    }

    /**
     * @notice Get total staked amount
     * @dev Convenience function, equivalent to totalSupply()
     * @return Total staked
     */
    function totalStaked() external view returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Override to make tokens non-transferable
     * @dev Allows minting/burning but blocks transfers between users
     */
    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        // Allow minting (from == 0) and burning (to == 0)
        // Block transfers between users
        if (from != address(0) && to != address(0)) {
            revert Errors.NonTransferable();
        }
        super._update(from, to, amount);
    }

    /**
     * @dev Required override for Nonces
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
