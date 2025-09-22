// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title ElataXP
 * @author Elata Biosciences
 * @notice Experience point system with 14-day rolling decay mechanism
 * @dev Non-transferable XP tokens that decay over time to encourage continuous participation
 *
 * Features:
 * - 14-day rolling window decay mechanism
 * - Checkpoint system for historical balance queries
 * - Auto-delegation for voting integration
 * - Batch operations for gas efficiency
 * - Keeper-compatible decay updates
 *
 * Decay Mechanism:
 * - XP decays linearly over 14 days
 * - Users must maintain activity to preserve XP
 * - Decay can be triggered by anyone (keeper function)
 * - Efficient batch decay processing
 */
contract ElataXP is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant XP_MINTER_ROLE = keccak256("XP_MINTER_ROLE");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Decay window duration (14 days)
    uint256 public constant DECAY_WINDOW = 14 days;

    /// @notice Minimum decay interval to prevent spam
    uint256 public constant MIN_DECAY_INTERVAL = 1 hours;

    struct XPEntry {
        uint256 amount;
        uint256 timestamp;
    }

    /// @notice User XP entries for decay calculation
    mapping(address => XPEntry[]) public userXPEntries;

    /// @notice Last decay update timestamp for each user
    mapping(address => uint256) public lastDecayUpdate;

    /// @notice Global last decay timestamp
    uint256 public lastGlobalDecay;

    /// @notice Total XP before decay calculations
    uint256 public totalXPBeforeDecay;

    event XPAwarded(address indexed user, uint256 amount, uint256 timestamp);
    event XPRevoked(address indexed user, uint256 amount);
    event XPDecayed(address indexed user, uint256 decayedAmount, uint256 newBalance);
    event BatchDecayProcessed(uint256 usersProcessed, uint256 totalDecayed);

    error DecayTooFrequent();
    error NoDecayNeeded();

    /**
     * @notice Initializes the XP contract with decay mechanics
     * @param admin Address that will receive admin roles
     */
    constructor(address admin) ERC20("Elata XP", "ELTAXP") ERC20Permit("Elata XP") {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(XP_MINTER_ROLE, admin);
        _grantRole(KEEPER_ROLE, admin);

        lastGlobalDecay = block.timestamp;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Awards XP to a user with timestamp tracking for decay
     * @param to Address to award XP to
     * @param amount Amount of XP to award
     */
    function award(address to, uint256 amount) external onlyRole(XP_MINTER_ROLE) {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();

        // Update decay before awarding new XP
        _updateUserDecay(to);

        // Add new XP entry
        userXPEntries[to].push(XPEntry({ amount: amount, timestamp: block.timestamp }));

        _mint(to, amount);
        totalXPBeforeDecay += amount;

        // Auto-delegate to self to enable checkpoint tracking
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        }

        emit XPAwarded(to, amount, block.timestamp);
    }

    /**
     * @notice Revokes XP from a user (removes most recent entries first)
     * @param from Address to revoke XP from
     * @param amount Amount of XP to revoke
     */
    function revoke(address from, uint256 amount) external onlyRole(XP_MINTER_ROLE) {
        if (from == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();

        // Update decay before revoking
        _updateUserDecay(from);

        uint256 remainingToRevoke = amount;
        XPEntry[] storage entries = userXPEntries[from];

        // Remove XP from most recent entries first
        for (uint256 i = entries.length; i > 0 && remainingToRevoke > 0; i--) {
            uint256 index = i - 1;
            XPEntry storage entry = entries[index];

            if (entry.amount <= remainingToRevoke) {
                remainingToRevoke -= entry.amount;
                totalXPBeforeDecay -= entry.amount;

                // Remove entry by swapping with last and popping
                entries[index] = entries[entries.length - 1];
                entries.pop();
            } else {
                entry.amount -= remainingToRevoke;
                totalXPBeforeDecay -= remainingToRevoke;
                remainingToRevoke = 0;
            }
        }

        _burn(from, amount);
        emit XPRevoked(from, amount);
    }

    /**
     * @notice Updates decay for a specific user
     * @param user Address to update decay for
     */
    function updateUserDecay(address user) external {
        _updateUserDecay(user);
    }

    /**
     * @notice Batch updates decay for multiple users (keeper function)
     * @param users Array of user addresses to update
     */
    function batchUpdateDecay(address[] calldata users) external onlyRole(KEEPER_ROLE) {
        if (block.timestamp < lastGlobalDecay + MIN_DECAY_INTERVAL) {
            revert DecayTooFrequent();
        }

        uint256 totalDecayed = 0;
        uint256 usersProcessed = 0;

        for (uint256 i = 0; i < users.length; i++) {
            uint256 decayed = _updateUserDecay(users[i]);
            if (decayed > 0) {
                totalDecayed += decayed;
                usersProcessed++;
            }
        }

        lastGlobalDecay = block.timestamp;
        emit BatchDecayProcessed(usersProcessed, totalDecayed);
    }

    /**
     * @notice Gets the effective XP balance after decay calculation
     * @param user User address
     * @return Effective XP balance
     */
    function effectiveBalance(address user) external view returns (uint256) {
        return _calculateEffectiveBalance(user);
    }

    /**
     * @notice Gets past XP balance at a specific block (for interface compatibility)
     * @param account User address
     * @param timepoint Block number
     * @return XP balance at the specified block
     */
    function getPastXP(address account, uint256 timepoint) external view returns (uint256) {
        return getPastVotes(account, timepoint);
    }

    /**
     * @notice Gets user's XP entries for decay calculation
     * @param user User address
     * @return Array of XP entries
     */
    function getUserXPEntries(address user) external view returns (XPEntry[] memory) {
        return userXPEntries[user];
    }

    /**
     * @notice Gets the total number of XP entries for a user
     * @param user User address
     * @return Number of XP entries
     */
    function getUserXPEntryCount(address user) external view returns (uint256) {
        return userXPEntries[user].length;
    }

    /**
     * @notice Gets comprehensive XP information for a user
     * @param user User address
     * @return currentBalance Current XP balance
     * @return currentEffectiveBalance Effective XP after decay
     * @return decayRate Current decay rate (basis points)
     * @return nextDecayAmount Amount that will decay next
     * @return timeToFullDecay Time until oldest XP fully decays
     */
    function getUserXPSummary(address user)
        external
        view
        returns (
            uint256 currentBalance,
            uint256 currentEffectiveBalance,
            uint256 decayRate,
            uint256 nextDecayAmount,
            uint256 timeToFullDecay
        )
    {
        currentBalance = balanceOf(user);
        currentEffectiveBalance = _calculateEffectiveBalance(user);

        if (currentBalance > 0) {
            decayRate = ((currentBalance - currentEffectiveBalance) * 10000) / currentBalance;
        } else {
            decayRate = 0;
        }

        nextDecayAmount = currentBalance - currentEffectiveBalance;
        timeToFullDecay = _calculateTimeToFullDecay(user);
    }

    /**
     * @notice Gets XP decay projection for a user
     * @param user User address
     * @param futureTimestamp Future timestamp to project to
     * @return projectedBalance Projected XP balance at future time
     */
    function getXPProjection(address user, uint256 futureTimestamp)
        external
        view
        returns (uint256 projectedBalance)
    {
        if (futureTimestamp <= block.timestamp) {
            return _calculateEffectiveBalance(user);
        }

        XPEntry[] storage entries = userXPEntries[user];
        projectedBalance = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            XPEntry storage entry = entries[i];
            uint256 age = futureTimestamp - entry.timestamp;

            if (age < DECAY_WINDOW) {
                uint256 decayFactor = DECAY_WINDOW - age;
                projectedBalance += (entry.amount * decayFactor) / DECAY_WINDOW;
            }
        }
    }

    /**
     * @notice Checks if user needs decay update (for frontend warnings)
     * @param user User address
     * @return needsUpdate Whether user should update decay
     * @return decayAmount Amount that would be decayed
     */
    function checkDecayStatus(address user)
        external
        view
        returns (bool needsUpdate, uint256 decayAmount)
    {
        uint256 currentBalance = balanceOf(user);
        uint256 currentEffectiveBalance = _calculateEffectiveBalance(user);

        needsUpdate = currentBalance > currentEffectiveBalance;
        decayAmount = needsUpdate ? currentBalance - currentEffectiveBalance : 0;
    }

    /**
     * @dev Updates decay for a user and burns decayed XP
     * @param user User address
     * @return Amount of XP decayed
     */
    function _updateUserDecay(address user) internal returns (uint256) {
        if (block.timestamp < lastDecayUpdate[user] + MIN_DECAY_INTERVAL) {
            return 0; // Skip if updated recently
        }

        uint256 currentBalance = balanceOf(user);
        uint256 calculatedEffectiveBalance = _calculateEffectiveBalance(user);

        if (currentBalance <= calculatedEffectiveBalance) {
            lastDecayUpdate[user] = block.timestamp;
            return 0; // No decay needed
        }

        uint256 decayAmount = currentBalance - calculatedEffectiveBalance;

        // Remove decayed entries
        _removeDecayedEntries(user);

        // Burn decayed XP
        _burn(user, decayAmount);
        totalXPBeforeDecay -= decayAmount;

        lastDecayUpdate[user] = block.timestamp;

        emit XPDecayed(user, decayAmount, calculatedEffectiveBalance);
        return decayAmount;
    }

    /**
     * @dev Calculates effective balance after decay
     * @param user User address
     * @return Effective balance
     */
    function _calculateEffectiveBalance(address user) internal view returns (uint256) {
        XPEntry[] storage entries = userXPEntries[user];
        uint256 totalEffectiveBalance = 0;
        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < entries.length; i++) {
            XPEntry storage entry = entries[i];
            uint256 age = currentTime - entry.timestamp;

            if (age < DECAY_WINDOW) {
                // Linear decay: amount * (DECAY_WINDOW - age) / DECAY_WINDOW
                uint256 decayFactor = DECAY_WINDOW - age;
                totalEffectiveBalance += (entry.amount * decayFactor) / DECAY_WINDOW;
            }
            // If age >= DECAY_WINDOW, entry contributes 0 (fully decayed)
        }

        return totalEffectiveBalance;
    }

    /**
     * @dev Removes fully decayed XP entries
     * @param user User address
     */
    function _removeDecayedEntries(address user) internal {
        XPEntry[] storage entries = userXPEntries[user];
        uint256 currentTime = block.timestamp;
        uint256 writeIndex = 0;

        // Compact array by removing decayed entries
        for (uint256 i = 0; i < entries.length; i++) {
            if (currentTime - entries[i].timestamp < DECAY_WINDOW) {
                if (writeIndex != i) {
                    entries[writeIndex] = entries[i];
                }
                writeIndex++;
            }
        }

        // Remove extra entries
        while (entries.length > writeIndex) {
            entries.pop();
        }
    }

    /**
     * @dev Calculates time until user's oldest XP fully decays
     * @param user User address
     * @return Time in seconds until full decay (0 if no XP)
     */
    function _calculateTimeToFullDecay(address user) internal view returns (uint256) {
        XPEntry[] storage entries = userXPEntries[user];
        if (entries.length == 0) return 0;

        uint256 oldestTimestamp = type(uint256).max;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].timestamp < oldestTimestamp) {
                oldestTimestamp = entries[i].timestamp;
            }
        }

        uint256 ageOfOldest = block.timestamp - oldestTimestamp;
        if (ageOfOldest >= DECAY_WINDOW) return 0;

        return DECAY_WINDOW - ageOfOldest;
    }

    /**
     * @dev Override to disable transfers (soulbound)
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        if (from != address(0) && to != address(0)) revert Errors.TransfersDisabled();
        super._update(from, to, value);
    }

    /**
     * @dev Required override for multiple inheritance
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
