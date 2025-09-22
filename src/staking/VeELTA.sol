// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title VeELTA (vote-escrowed ELTA)
 * @notice Minimal ve-style staking with linear time-decay of voting power.
 *         - One active lock per address in this v1 (simple & safe).
 *         - Voting power: amount * (timeRemaining / MAX_LOCK).
 *         - MAX_LOCK and MIN_LOCK are constants; adjust as needed.
 *         - Not transferable. Use views to fetch voting power per account.
 *
 * Notes:
 * - This is intentionally minimal scaffolding. A future v2 can migrate to an
 *   ERC721 "non-transferable positions" model if multi-locks are required.
 */
contract VeELTA is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IERC20 public immutable ELTA;

    uint256 public constant MIN_LOCK = 1 weeks;
    uint256 public constant MAX_LOCK = 104 weeks; // 2 years (tunable)

    struct Lock {
        uint128 amount; // staked ELTA
        uint64 start; // lock start (timestamp)
        uint64 end; // lock end (timestamp)
    }

    mapping(address => Lock) public locks;

    event LockCreated(address indexed user, uint256 amount, uint256 start, uint256 end);
    event LockIncreased(address indexed user, uint256 addedAmount, uint256 newAmount);
    event UnlockExtended(address indexed user, uint256 oldEnd, uint256 newEnd);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(IERC20 elta, address admin) {
        if (address(elta) == address(0) || admin == address(0)) revert Errors.ZeroAddress();
        ELTA = elta;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    /// @notice Create a new lock. Reverts if user already has an active lock.
    function createLock(uint256 amount, uint256 lockDuration) external nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();
        if (lockDuration < MIN_LOCK) revert Errors.LockTooShort();
        if (lockDuration > MAX_LOCK) revert Errors.LockTooLong();

        Lock memory l = locks[msg.sender];
        if (l.amount > 0 && block.timestamp < l.end) revert Errors.LockActive();

        // pull tokens
        ELTA.safeTransferFrom(msg.sender, address(this), amount);

        uint64 start = uint64(block.timestamp);
        uint64 end = uint64(block.timestamp + lockDuration);
        locks[msg.sender] = Lock(uint128(amount), start, end);

        emit LockCreated(msg.sender, amount, start, end);
    }

    /// @notice Add more ELTA to an existing active lock.
    function increaseAmount(uint256 added) external nonReentrant {
        if (added == 0) revert Errors.InvalidAmount();

        Lock storage l = locks[msg.sender];
        if (l.amount == 0 || block.timestamp >= l.end) revert Errors.NoActiveLock();

        ELTA.safeTransferFrom(msg.sender, address(this), added);
        l.amount = uint128(uint256(l.amount) + added);

        emit LockIncreased(msg.sender, added, l.amount);
    }

    /// @notice Extend lock end time (cannot reduce, cannot exceed MAX_LOCK from original start).
    function increaseUnlockTime(uint256 newEnd) external {
        Lock storage l = locks[msg.sender];
        if (l.amount == 0 || block.timestamp >= l.end) revert Errors.NoActiveLock();
        if (newEnd <= l.end) revert Errors.LockTooShort();

        // enforce max from original start
        uint256 maxAllowed = uint256(l.start) + MAX_LOCK;
        if (newEnd > maxAllowed) revert Errors.LockTooLong();

        uint64 oldEnd = l.end;
        l.end = uint64(newEnd);
        emit UnlockExtended(msg.sender, oldEnd, newEnd);
    }

    /// @notice Withdraw after expiry.
    function withdraw() external nonReentrant {
        Lock storage l = locks[msg.sender];
        if (l.amount == 0) revert Errors.NoActiveLock();
        if (block.timestamp < l.end) revert Errors.LockNotExpired();

        uint256 amount = l.amount;
        delete locks[msg.sender];

        ELTA.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Current voting power for an account.
    function votingPower(address account) public view returns (uint256) {
        Lock memory l = locks[account];
        if (l.amount == 0 || block.timestamp >= l.end) return 0;

        uint256 remaining = uint256(l.end) - block.timestamp;
        // amount * remaining / MAX_LOCK
        return (uint256(l.amount) * remaining) / MAX_LOCK;
    }
}
