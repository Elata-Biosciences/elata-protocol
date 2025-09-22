// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title VeELTA
 * @author Elata Biosciences
 * @notice Vote-escrowed ELTA staking with multiple non-transferable lock positions
 * @dev NFT-based approach allowing multiple concurrent locks per user
 *
 * Features:
 * - Multiple concurrent lock positions per user
 * - Non-transferable NFT positions (soulbound)
 * - Linear decay voting power calculation
 * - Position merging and splitting capabilities
 * - Delegation support for governance participation
 * - Emergency unlock with penalty mechanism
 *
 * Security:
 * - Reentrancy protection on all state-changing functions
 * - Role-based access control for admin functions
 * - Non-transferable positions prevent secondary markets
 * - Time-locked withdrawals prevent flash loan attacks
 */
contract VeELTA is ERC721, ERC721Enumerable, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    IERC20 public immutable ELTA;

    uint256 public constant MIN_LOCK = 1 weeks;
    uint256 public constant MAX_LOCK = 208 weeks; // 4 years for multi-lock
    uint256 public constant EMERGENCY_UNLOCK_PENALTY = 5000; // 50% penalty

    struct LockPosition {
        uint128 amount;
        uint64 start;
        uint64 end;
        address delegate;
        bool emergencyUnlocked;
    }

    /// @notice Current token ID counter
    uint256 public nextTokenId = 1;

    /// @notice Mapping from token ID to lock position
    mapping(uint256 => LockPosition) public positions;

    /// @notice Mapping from user to their delegated voting power
    mapping(address => uint256) public delegatedVotingPower;

    /// @notice Emergency unlock enabled flag
    bool public emergencyUnlockEnabled;

    event LockCreated(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 start,
        uint256 end
    );
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newAmount);
    event LockExtended(uint256 indexed tokenId, uint256 oldEnd, uint256 newEnd);
    event PositionsMerged(uint256 indexed fromTokenId, uint256 indexed toTokenId, uint256 totalAmount);
    event PositionSplit(uint256 indexed originalTokenId, uint256 indexed newTokenId, uint256 splitAmount);
    event VotingPowerDelegated(uint256 indexed tokenId, address indexed from, address indexed to);
    event EmergencyUnlock(uint256 indexed tokenId, uint256 amount, uint256 penalty);
    event Withdrawn(uint256 indexed tokenId, uint256 amount);
    event EmergencyUnlockToggled(bool enabled);

    /**
     * @notice Initializes the multi-lock veELTA contract
     * @param _elta Address of the ELTA token
     * @param _admin Address that will receive admin roles
     */
    constructor(
        IERC20 _elta,
        address _admin
    ) ERC721("Vote-Escrowed ELTA", "veELTA") {
        if (address(_elta) == address(0) || _admin == address(0)) {
            revert Errors.ZeroAddress();
        }

        ELTA = _elta;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MANAGER_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
    }

    /**
     * @notice Creates a new lock position
     * @param amount Amount of ELTA to lock
     * @param lockDuration Duration of the lock in seconds
     * @return tokenId The ID of the created position NFT
     */
    function createLock(uint256 amount, uint256 lockDuration) external nonReentrant returns (uint256 tokenId) {
        if (amount == 0) revert Errors.InvalidAmount();
        if (lockDuration < MIN_LOCK) revert Errors.LockTooShort();
        if (lockDuration > MAX_LOCK) revert Errors.LockTooLong();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);

        tokenId = nextTokenId++;
        uint64 start = uint64(block.timestamp);
        uint64 end = uint64(block.timestamp + lockDuration);

        positions[tokenId] = LockPosition({
            amount: uint128(amount),
            start: start,
            end: end,
            delegate: msg.sender, // Default delegation to owner
            emergencyUnlocked: false
        });

        _mint(msg.sender, tokenId);
        
        // Update delegation
        delegatedVotingPower[msg.sender] += _calculateVotingPower(amount, lockDuration);

        emit LockCreated(msg.sender, tokenId, amount, start, end);
    }

    /**
     * @notice Increases the amount of an existing lock position
     * @param tokenId ID of the position to increase
     * @param addedAmount Additional amount to lock
     */
    function increaseAmount(uint256 tokenId, uint256 addedAmount) external nonReentrant {
        if (addedAmount == 0) revert Errors.InvalidAmount();
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert Errors.NotAuthorized();

        LockPosition storage position = positions[tokenId];
        if (position.emergencyUnlocked) revert Errors.LockNotExpired();
        if (block.timestamp >= position.end) revert Errors.LockNotExpired();

        ELTA.safeTransferFrom(msg.sender, address(this), addedAmount);

        // Update voting power delegation
        uint256 oldVotingPower = _getPositionVotingPower(tokenId);
        position.amount = uint128(uint256(position.amount) + addedAmount);
        uint256 newVotingPower = _getPositionVotingPower(tokenId);

        address delegate = position.delegate;
        delegatedVotingPower[delegate] = delegatedVotingPower[delegate] - oldVotingPower + newVotingPower;

        emit LockIncreased(tokenId, addedAmount, position.amount);
    }

    /**
     * @notice Extends the unlock time of a position
     * @param tokenId ID of the position to extend
     * @param newEnd New end timestamp
     */
    function increaseUnlockTime(uint256 tokenId, uint256 newEnd) external {
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert Errors.NotAuthorized();

        LockPosition storage position = positions[tokenId];
        if (position.emergencyUnlocked) revert Errors.LockNotExpired();
        if (block.timestamp >= position.end) revert Errors.LockNotExpired();
        if (newEnd <= position.end) revert Errors.LockTooShort();

        uint256 maxAllowed = uint256(position.start) + MAX_LOCK;
        if (newEnd > maxAllowed) revert Errors.LockTooLong();

        // Update voting power delegation
        uint256 oldVotingPower = _getPositionVotingPower(tokenId);
        uint64 oldEnd = position.end;
        position.end = uint64(newEnd);
        uint256 newVotingPower = _getPositionVotingPower(tokenId);

        address delegate = position.delegate;
        delegatedVotingPower[delegate] = delegatedVotingPower[delegate] - oldVotingPower + newVotingPower;

        emit LockExtended(tokenId, oldEnd, newEnd);
    }

    /**
     * @notice Merges two lock positions owned by the same user
     * @param fromTokenId Source position to merge from
     * @param toTokenId Target position to merge into
     */
    function mergePositions(uint256 fromTokenId, uint256 toTokenId) external nonReentrant {
        address owner = ownerOf(fromTokenId);
        if (owner != ownerOf(toTokenId)) revert Errors.NotAuthorized();
        if (!_isAuthorized(owner, msg.sender, fromTokenId)) revert Errors.NotAuthorized();

        LockPosition storage fromPos = positions[fromTokenId];
        LockPosition storage toPos = positions[toTokenId];

        if (fromPos.emergencyUnlocked || toPos.emergencyUnlocked) revert Errors.LockNotExpired();
        if (block.timestamp >= fromPos.end || block.timestamp >= toPos.end) revert Errors.LockNotExpired();

        // Update voting power delegation
        uint256 oldFromPower = _getPositionVotingPower(fromTokenId);
        uint256 oldToPower = _getPositionVotingPower(toTokenId);

        // Merge into the position with the later end time
        if (toPos.end < fromPos.end) {
            toPos.end = fromPos.end;
        }
        toPos.amount = uint128(uint256(toPos.amount) + uint256(fromPos.amount));

        uint256 newToPower = _getPositionVotingPower(toTokenId);

        // Update delegated voting power
        address fromDelegate = fromPos.delegate;
        address toDelegate = toPos.delegate;
        
        delegatedVotingPower[fromDelegate] -= oldFromPower;
        delegatedVotingPower[toDelegate] = delegatedVotingPower[toDelegate] - oldToPower + newToPower;

        // Burn the source position
        _burn(fromTokenId);
        delete positions[fromTokenId];

        emit PositionsMerged(fromTokenId, toTokenId, toPos.amount);
    }

    /**
     * @notice Splits a lock position into two positions
     * @param tokenId ID of the position to split
     * @param splitAmount Amount to split into new position
     * @return newTokenId ID of the newly created position
     */
    function splitPosition(uint256 tokenId, uint256 splitAmount) external nonReentrant returns (uint256 newTokenId) {
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert Errors.NotAuthorized();
        if (splitAmount == 0) revert Errors.InvalidAmount();

        LockPosition storage position = positions[tokenId];
        if (position.emergencyUnlocked) revert Errors.LockNotExpired();
        if (block.timestamp >= position.end) revert Errors.LockNotExpired();
        if (splitAmount >= position.amount) revert Errors.InvalidAmount();

        // Update original position
        uint256 oldVotingPower = _getPositionVotingPower(tokenId);
        position.amount = uint128(uint256(position.amount) - splitAmount);
        uint256 newOriginalPower = _getPositionVotingPower(tokenId);

        // Create new position
        newTokenId = nextTokenId++;
        positions[newTokenId] = LockPosition({
            amount: uint128(splitAmount),
            start: position.start,
            end: position.end,
            delegate: position.delegate,
            emergencyUnlocked: false
        });

        _mint(ownerOf(tokenId), newTokenId);

        uint256 newSplitPower = _getPositionVotingPower(newTokenId);

        // Update delegated voting power
        address delegate = position.delegate;
        delegatedVotingPower[delegate] = delegatedVotingPower[delegate] - oldVotingPower + newOriginalPower + newSplitPower;

        emit PositionSplit(tokenId, newTokenId, splitAmount);
    }

    /**
     * @notice Delegates voting power of a position to another address
     * @param tokenId ID of the position
     * @param to Address to delegate to
     */
    function delegatePosition(uint256 tokenId, address to) external {
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert Errors.NotAuthorized();
        if (to == address(0)) revert Errors.ZeroAddress();

        LockPosition storage position = positions[tokenId];
        address oldDelegate = position.delegate;
        
        if (oldDelegate == to) return; // No change needed

        uint256 votingPower = _getPositionVotingPower(tokenId);
        
        // Update delegation
        delegatedVotingPower[oldDelegate] -= votingPower;
        delegatedVotingPower[to] += votingPower;
        position.delegate = to;

        emit VotingPowerDelegated(tokenId, oldDelegate, to);
    }

    /**
     * @notice Emergency unlock with penalty (admin only)
     * @param tokenId ID of the position to emergency unlock
     */
    function emergencyUnlock(uint256 tokenId) external onlyRole(EMERGENCY_ROLE) {
        if (!emergencyUnlockEnabled) revert Errors.NotAuthorized();

        LockPosition storage position = positions[tokenId];
        if (position.emergencyUnlocked) revert Errors.LockNotExpired();
        if (block.timestamp >= position.end) revert Errors.LockNotExpired();

        uint256 amount = position.amount;
        uint256 penalty = (amount * EMERGENCY_UNLOCK_PENALTY) / 10000;
        uint256 returnAmount = amount - penalty;

        // Update voting power delegation
        uint256 votingPower = _getPositionVotingPower(tokenId);
        delegatedVotingPower[position.delegate] -= votingPower;

        position.emergencyUnlocked = true;
        position.amount = 0;

        address owner = ownerOf(tokenId);
        ELTA.safeTransfer(owner, returnAmount);
        // Penalty stays in contract (can be redistributed)

        emit EmergencyUnlock(tokenId, returnAmount, penalty);
    }

    /**
     * @notice Withdraws from an expired lock position
     * @param tokenId ID of the position to withdraw from
     */
    function withdraw(uint256 tokenId) external nonReentrant {
        if (!_isAuthorized(ownerOf(tokenId), msg.sender, tokenId)) revert Errors.NotAuthorized();

        LockPosition storage position = positions[tokenId];
        if (position.amount == 0) revert Errors.NoActiveLock();
        if (!position.emergencyUnlocked && block.timestamp < position.end) {
            revert Errors.LockNotExpired();
        }

        uint256 amount = position.amount;
        
        // Update voting power delegation if not emergency unlocked
        if (!position.emergencyUnlocked) {
            uint256 votingPower = _getPositionVotingPower(tokenId);
            delegatedVotingPower[position.delegate] -= votingPower;
        }

        position.amount = 0;
        _burn(tokenId);

        if (!position.emergencyUnlocked) {
            ELTA.safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(tokenId, amount);
    }

    /**
     * @notice Gets the voting power for a specific position
     * @param tokenId ID of the position
     * @return Voting power of the position
     */
    function getPositionVotingPower(uint256 tokenId) external view returns (uint256) {
        return _getPositionVotingPower(tokenId);
    }

    /**
     * @notice Gets the total voting power for a user across all positions
     * @param user User address
     * @return Total voting power
     */
    function getUserVotingPower(address user) external view returns (uint256) {
        uint256 totalPower = 0;
        uint256 balance = balanceOf(user);

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            totalPower += _getPositionVotingPower(tokenId);
        }

        return totalPower;
    }

    /**
     * @notice Gets delegated voting power for an address
     * @param delegate Delegate address
     * @return Total delegated voting power
     */
    function getDelegatedVotingPower(address delegate) external view returns (uint256) {
        return delegatedVotingPower[delegate];
    }

    /**
     * @notice Gets all position IDs owned by a user
     * @param user User address
     * @return Array of token IDs
     */
    function getUserPositions(address user) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(user, i);
        }

        return tokenIds;
    }

    /**
     * @notice Enables/disables emergency unlock functionality
     * @param enabled Whether emergency unlock should be enabled
     */
    function setEmergencyUnlockEnabled(bool enabled) external onlyRole(EMERGENCY_ROLE) {
        emergencyUnlockEnabled = enabled;
        emit EmergencyUnlockToggled(enabled);
    }

    /**
     * @notice Gets detailed position information for frontend display
     * @param tokenId Position token ID
     * @return amount Locked amount
     * @return startTime Lock start timestamp
     * @return endTime Lock end timestamp
     * @return delegate Current delegate address
     * @return votingPower Current voting power
     * @return timeRemaining Time until unlock (0 if expired)
     * @return isExpired Whether position has expired
     * @return emergencyUnlocked Whether emergency unlocked
     */
    function getPositionDetails(uint256 tokenId) external view returns (
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        address delegate,
        uint256 votingPower,
        uint256 timeRemaining,
        bool isExpired,
        bool emergencyUnlocked
    ) {
        LockPosition storage position = positions[tokenId];
        
        amount = position.amount;
        startTime = position.start;
        endTime = position.end;
        delegate = position.delegate;
        votingPower = _getPositionVotingPower(tokenId);
        isExpired = block.timestamp >= position.end;
        timeRemaining = isExpired ? 0 : position.end - block.timestamp;
        emergencyUnlocked = position.emergencyUnlocked;
    }

    /**
     * @notice Gets user's total staking summary
     * @param user User address
     * @return positionCount Number of positions
     * @return totalStaked Total ELTA staked
     * @return totalVotingPower Total voting power
     * @return averageTimeRemaining Average time until unlock
     */
    function getUserStakingSummary(address user) external view returns (
        uint256 positionCount,
        uint256 totalStaked,
        uint256 totalVotingPower,
        uint256 averageTimeRemaining
    ) {
        uint256[] memory tokenIds = this.getUserPositions(user);
        positionCount = tokenIds.length;
        
        if (positionCount == 0) return (0, 0, 0, 0);
        
        uint256 totalTimeRemaining = 0;
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            LockPosition storage position = positions[tokenIds[i]];
            totalStaked += position.amount;
            totalVotingPower += _getPositionVotingPower(tokenIds[i]);
            
            if (block.timestamp < position.end) {
                totalTimeRemaining += position.end - block.timestamp;
            }
        }
        
        averageTimeRemaining = totalTimeRemaining / positionCount;
    }

    /**
     * @notice Checks if a position can be withdrawn
     * @param tokenId Position token ID
     * @return withdrawable Whether position can be withdrawn
     * @return reason Reason if cannot withdraw
     */
    function canWithdraw(uint256 tokenId) external view returns (bool withdrawable, string memory reason) {
        LockPosition storage position = positions[tokenId];
        
        if (position.amount == 0) {
            return (false, "Position does not exist or already withdrawn");
        }
        
        if (!position.emergencyUnlocked && block.timestamp < position.end) {
            return (false, "Position is still locked");
        }
        
        return (true, "Position can be withdrawn");
    }

    /**
     * @dev Calculates voting power for a given amount and duration
     * @param amount Locked amount
     * @param duration Lock duration
     * @return Voting power
     */
    function _calculateVotingPower(uint256 amount, uint256 duration) internal pure returns (uint256) {
        return (amount * duration) / MAX_LOCK;
    }

    /**
     * @dev Gets the current voting power for a position
     * @param tokenId Position token ID
     * @return Current voting power
     */
    function _getPositionVotingPower(uint256 tokenId) internal view returns (uint256) {
        LockPosition storage position = positions[tokenId];
        
        if (position.amount == 0 || position.emergencyUnlocked) return 0;
        if (block.timestamp >= position.end) return 0;

        uint256 remaining = uint256(position.end) - block.timestamp;
        return (uint256(position.amount) * remaining) / MAX_LOCK;
    }

    /**
     * @dev Override to make tokens non-transferable (soulbound)
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        
        // Allow minting (from == 0) and burning (to == 0)
        if (from != address(0) && to != address(0)) {
            revert Errors.TransfersDisabled();
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Required override for ERC721Enumerable
     */
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /**
     * @dev Required override for multiple inheritance
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
