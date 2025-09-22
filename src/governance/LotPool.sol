// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ElataXP } from "../experience/ElataXP.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title LotPool
 * @notice Simple XP-weighted weekly funding round for experiments/apps.
 *         - On start, takes an XP snapshot (via ElataXP).
 *         - Voters allocate their XP-at-snapshot across options.
 *         - Admin finalizes and pays out funds from this contract.
 *
 * Security:
 * - This is minimal scaffolding (no on-chain parameter governance).
 * - Gate admin functions behind your multisig/DAO.
 */
contract LotPool is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IERC20 public immutable ELTA;
    ElataXP public immutable XP;

    struct Round {
        uint256 snapshotBlock; // block number for XP snapshot
        uint64 start;
        uint64 end;
        bool finalized;
        bytes32[] options; // opaque ids; e.g., keccak256("EXP-123")
        mapping(bytes32 => uint256) votes; // option => total XP votes
        mapping(address => uint256) used; // voter => XP already used in this round
        mapping(bytes32 => address) recipient; // option => payout recipient
    }

    uint256 public currentRoundId;
    mapping(uint256 => Round) private _rounds;

    event RoundStarted(uint256 indexed roundId, uint256 snapshotBlock, uint64 start, uint64 end);
    event OptionAdded(uint256 indexed roundId, bytes32 option, address recipient);
    event Voted(uint256 indexed roundId, address indexed voter, bytes32 option, uint256 weight);
    event Finalized(uint256 indexed roundId, bytes32 winner, uint256 amount, address recipient);

    constructor(IERC20 elta, ElataXP xp, address admin) {
        if (address(elta) == address(0) || address(xp) == address(0) || admin == address(0)) {
            revert Errors.ZeroAddress();
        }
        ELTA = elta;
        XP = xp;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    function getRound(uint256 roundId)
        external
        view
        returns (
            uint256 snapshotBlock,
            uint64 start,
            uint64 end,
            bool finalized,
            bytes32[] memory options
        )
    {
        Round storage r = _rounds[roundId];
        snapshotBlock = r.snapshotBlock;
        start = r.start;
        end = r.end;
        finalized = r.finalized;
        options = r.options;
    }

    /// @notice Fund the pool (ELTA) prior to or during an active round.
    function fund(uint256 amount) external {
        if (amount == 0) revert Errors.InvalidAmount();
        ELTA.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Start a new round: captures current block for XP snapshot; defines options & recipients.
    function startRound(
        bytes32[] calldata options,
        address[] calldata recipients,
        uint64 durationSecs
    ) external onlyRole(MANAGER_ROLE) returns (uint256 roundId, uint256 snapshotBlock) {
        if (options.length == 0 || options.length != recipients.length) {
            revert Errors.ArrayLengthMismatch();
        }
        uint64 start = uint64(block.timestamp);
        uint64 end = start + durationSecs;

        roundId = ++currentRoundId;
        Round storage r = _rounds[roundId];

        // Use current block number - 1 to ensure it's finalized
        snapshotBlock = block.number > 0 ? block.number - 1 : 0;
        r.snapshotBlock = snapshotBlock;
        r.start = start;
        r.end = end;

        // add options
        for (uint256 i = 0; i < options.length; i++) {
            bytes32 opt = options[i];
            address rcpt = recipients[i];
            if (rcpt == address(0)) revert Errors.ZeroAddress();

            // avoid duplicates
            for (uint256 j = 0; j < r.options.length; j++) {
                if (r.options[j] == opt) revert Errors.DuplicateOption();
            }
            r.options.push(opt);
            r.recipient[opt] = rcpt;

            emit OptionAdded(roundId, opt, rcpt);
        }

        emit RoundStarted(roundId, snapshotBlock, start, end);
    }

    /// @notice Cast XP-weighted votes (consumes your XP-at-snapshot for this round).
    function vote(uint256 roundId, bytes32 option, uint256 weight) external {
        Round storage r = _rounds[roundId];
        if (block.timestamp < r.start) revert Errors.VotingNotStarted();
        if (block.timestamp > r.end) revert Errors.VotingClosed();

        // ensure option exists
        bool exists;
        for (uint256 i = 0; i < r.options.length; i++) {
            if (r.options[i] == option) {
                exists = true;
                break;
            }
        }
        if (!exists) revert Errors.DuplicateOption(); // reuse error for "invalid option"

        uint256 voterXP = XP.getPastXP(msg.sender, r.snapshotBlock);
        uint256 used = r.used[msg.sender];
        if (weight == 0 || voterXP < used + weight) revert Errors.InsufficientXP();

        r.used[msg.sender] = used + weight;
        r.votes[option] += weight;

        emit Voted(roundId, msg.sender, option, weight);
    }

    /// @notice Read total votes for an option in a round.
    function votesFor(uint256 roundId, bytes32 option) external view returns (uint256) {
        return _rounds[roundId].votes[option];
    }

    /// @notice Finalize a round and pay out `amount` ELTA to the winner's recipient.
    function finalize(uint256 roundId, bytes32 winner, uint256 amount)
        external
        onlyRole(MANAGER_ROLE)
    {
        Round storage r = _rounds[roundId];
        if (r.finalized) revert();
        if (block.timestamp <= r.end) revert Errors.VotingClosed();

        // Confirm winner is a valid option
        bool exists;
        for (uint256 i = 0; i < r.options.length; i++) {
            if (r.options[i] == winner) {
                exists = true;
                break;
            }
        }
        if (!exists) revert Errors.DuplicateOption();

        r.finalized = true;

        address rcpt = r.recipient[winner];
        if (amount > 0) {
            ELTA.safeTransfer(rcpt, amount);
        }

        emit Finalized(roundId, winner, amount, rcpt);
    }
}
