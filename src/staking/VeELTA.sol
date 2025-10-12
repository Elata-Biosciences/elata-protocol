// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Errors } from "../utils/Errors.sol";
import { IVeEltaVotes } from "../interfaces/IVeEltaVotes.sol";

/**
 * @title VeELTA (Vote-Escrowed ELTA)
 * @author Elata Biosciences
 * @notice Non-transferable ERC20Votes token representing voting power from locked ELTA
 * @dev Snapshot-enabled for on-chain reward distribution and governance
 *
 * Architecture:
 * - Users lock ELTA for a duration (MIN_LOCK to MAX_LOCK)
 * - veELTA minted = principal * boost(duration)
 * - No continuous decay; voting power updates only on user actions
 * - Principal returned 1:1 on unlock (veELTA burned)
 *
 * Features:
 * - lock(): Create new lock position
 * - increaseAmount(): Add more ELTA to existing lock
 * - extendLock(): Extend unlock time
 * - unlock(): Withdraw principal after expiry
 * - ERC20Votes snapshots for governance and rewards
 * - Non-transferable (soulbound to staker)
 */
contract VeELTA is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    error LockExists();
    error LockExpired();
    error InvalidUnlockTime();
    error Insufficient();

    IERC20 public immutable ELTA;

    uint64 public constant MIN_LOCK = 7 days;
    uint64 public constant MAX_LOCK = 730 days; // 2 years

    /// @notice Boost values (1e18 = 1x)
    uint256 public constant BOOST_MIN = 1e18; // 1.00x at MIN_LOCK
    uint256 public constant BOOST_MAX = 2e18; // 2.00x at MAX_LOCK

    /// @notice User lock data
    struct Lock {
        uint128 principal; // ELTA locked (never decays)
        uint64 unlockTime; // When user can withdraw
    }

    mapping(address => Lock) public locks;

    event Locked(address indexed user, uint256 amount, uint64 unlockTime, uint256 veELTA);
    event AmountIncreased(
        address indexed user, uint256 addAmount, uint256 newPrincipal, uint256 newVeELTA
    );
    event LockExtended(
        address indexed user, uint64 oldUnlockTime, uint64 newUnlockTime, uint256 newVeELTA
    );
    event Unlocked(address indexed user, uint256 principal, uint256 veELTABurned);

    /**
     * @notice Initialize veELTA
     * @param _elta ELTA token address
     * @param _admin Admin address for roles
     */
    constructor(IERC20 _elta, address _admin)
        ERC20("veELTA Voting Power", "veELTA")
        ERC20Permit("veELTA Voting Power")
    {
        if (address(_elta) == address(0) || _admin == address(0)) {
            revert Errors.ZeroAddress();
        }

        ELTA = _elta;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
    }

    /**
     * @notice Create a new lock position
     * @dev User must have no existing lock
     * @param amount ELTA amount to lock
     * @param unlockTime Unix timestamp when lock expires
     */
    function lock(uint256 amount, uint64 unlockTime) external {
        Lock memory userLock = locks[msg.sender];
        if (userLock.principal > 0) revert LockExists();
        if (amount == 0) revert Errors.InvalidAmount();
        if (unlockTime <= block.timestamp + MIN_LOCK) revert Errors.LockTooShort();
        if (unlockTime > block.timestamp + MAX_LOCK) revert Errors.LockTooLong();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);

        uint256 duration = unlockTime - uint64(block.timestamp);
        uint256 boost = _calculateBoost(duration);
        uint256 veAmount = (amount * boost) / 1e18;

        locks[msg.sender] = Lock({ principal: uint128(amount), unlockTime: unlockTime });

        _mint(msg.sender, veAmount);

        // Auto-delegate to self for voting power (ERC20Votes requirement)
        if (delegates(msg.sender) == address(0)) {
            _delegate(msg.sender, msg.sender);
        }

        emit Locked(msg.sender, amount, unlockTime, veAmount);
    }

    /**
     * @notice Add more ELTA to existing lock
     * @dev Recalculates voting power based on remaining duration
     * @param amount Additional ELTA to lock
     */
    function increaseAmount(uint256 amount) external {
        Lock memory userLock = locks[msg.sender];
        if (userLock.principal == 0) revert Errors.NoActiveLock();
        if (block.timestamp >= userLock.unlockTime) revert LockExpired();
        if (amount == 0) revert Errors.InvalidAmount();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);

        uint256 remainingTime = userLock.unlockTime - uint64(block.timestamp);
        uint256 boost = _calculateBoost(remainingTime);

        // Calculate old and new voting power
        uint256 oldVeAmount = (uint256(userLock.principal) * boost) / 1e18;
        uint256 newPrincipal = uint256(userLock.principal) + amount;
        uint256 newVeAmount = (newPrincipal * boost) / 1e18;

        locks[msg.sender].principal = uint128(newPrincipal);

        // Mint difference
        if (newVeAmount > oldVeAmount) {
            _mint(msg.sender, newVeAmount - oldVeAmount);
        } else if (oldVeAmount > newVeAmount) {
            _burn(msg.sender, oldVeAmount - newVeAmount);
        }

        emit AmountIncreased(msg.sender, amount, newPrincipal, newVeAmount);
    }

    /**
     * @notice Extend lock duration
     * @dev Recalculates voting power based on new duration
     * @param newUnlockTime New unlock timestamp (must be > current)
     */
    function extendLock(uint64 newUnlockTime) external {
        Lock memory userLock = locks[msg.sender];
        if (userLock.principal == 0) revert Errors.NoActiveLock();
        if (newUnlockTime <= userLock.unlockTime) revert InvalidUnlockTime();
        if (newUnlockTime > block.timestamp + MAX_LOCK) revert Errors.LockTooLong();

        uint256 oldRemainingTime = userLock.unlockTime > block.timestamp
            ? userLock.unlockTime - uint64(block.timestamp)
            : 0;
        uint256 newRemainingTime = newUnlockTime - uint64(block.timestamp);

        uint256 oldBoost = _calculateBoost(oldRemainingTime);
        uint256 newBoost = _calculateBoost(newRemainingTime);

        uint256 oldVeAmount = (uint256(userLock.principal) * oldBoost) / 1e18;
        uint256 newVeAmount = (uint256(userLock.principal) * newBoost) / 1e18;

        locks[msg.sender].unlockTime = newUnlockTime;

        // Adjust voting power
        if (newVeAmount > oldVeAmount) {
            _mint(msg.sender, newVeAmount - oldVeAmount);
        } else if (oldVeAmount > newVeAmount) {
            _burn(msg.sender, oldVeAmount - newVeAmount);
        }

        emit LockExtended(msg.sender, userLock.unlockTime, newUnlockTime, newVeAmount);
    }

    /**
     * @notice Unlock and withdraw ELTA principal
     * @dev Burns all veELTA and returns 1:1 ELTA principal
     */
    function unlock() external {
        Lock memory userLock = locks[msg.sender];
        if (userLock.principal == 0) revert Errors.NoActiveLock();
        if (block.timestamp < userLock.unlockTime) revert Errors.LockNotExpired();

        uint256 principal = userLock.principal;
        uint256 veBalance = balanceOf(msg.sender);

        delete locks[msg.sender];

        if (veBalance > 0) {
            _burn(msg.sender, veBalance);
        }

        ELTA.safeTransfer(msg.sender, principal);

        emit Unlocked(msg.sender, principal, veBalance);
    }

    /**
     * @notice Admin mint for migration/governance
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MANAGER_ROLE) {
        _mint(to, amount);

        // Auto-delegate to self for voting power
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        }
    }

    /**
     * @notice Admin burn for migration/governance
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyRole(MANAGER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @notice Calculate duration boost (linear interpolation)
     * @dev Boost ranges from 1x (MIN_LOCK) to 2x (MAX_LOCK)
     * @param duration Lock duration in seconds
     * @return boost Boost multiplier (1e18 = 1x)
     */
    function _calculateBoost(uint256 duration) internal pure returns (uint256 boost) {
        if (duration >= MAX_LOCK) return BOOST_MAX;
        if (duration <= MIN_LOCK) return BOOST_MIN;

        // Linear interpolation: boost = 1e18 + (1e18 * duration / MAX_LOCK)
        boost = BOOST_MIN + ((BOOST_MAX - BOOST_MIN) * duration) / MAX_LOCK;
    }

    /**
     * @notice Get lock details for a user
     * @param user User address
     * @return principal ELTA locked
     * @return unlockTime Unlock timestamp
     * @return veBalance Current veELTA balance
     * @return isExpired Whether lock has expired
     */
    function getLockDetails(address user)
        external
        view
        returns (uint256 principal, uint64 unlockTime, uint256 veBalance, bool isExpired)
    {
        Lock memory userLock = locks[user];
        principal = userLock.principal;
        unlockTime = userLock.unlockTime;
        veBalance = balanceOf(user);
        isExpired = block.timestamp >= unlockTime;
    }

    /**
     * @notice Check if user can unlock
     * @param user User address
     * @return unlockable Whether user can unlock now
     * @return timeRemaining Seconds until unlock (0 if expired)
     */
    function canUnlock(address user)
        external
        view
        returns (bool unlockable, uint256 timeRemaining)
    {
        Lock memory userLock = locks[user];
        if (userLock.principal == 0) return (false, 0);

        if (block.timestamp >= userLock.unlockTime) {
            return (true, 0);
        } else {
            return (false, userLock.unlockTime - block.timestamp);
        }
    }

    /**
     * @dev Override to make tokens non-transferable (soulbound)
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
