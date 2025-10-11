// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Tournament
 * @author Elata Protocol
 * @notice Entry-fee tournaments with protocol & burn fees, Merkle-claim winners
 * @dev On-chain paid competitions with transparent payouts
 *
 * Key Features:
 * - Entry fee pool accumulation
 * - Protocol fee to treasury
 * - Burn fee for deflationary pressure
 * - Merkle proof winner claims
 * - One-time finalization
 *
 * Tournament Flow:
 * 1. Deploy tournament with parameters
 * 2. Users enter during time window (pay entry fee)
 * 3. Owner finalizes with Merkle root of winners
 * 4. Winners claim rewards with proofs
 */
contract Tournament is Ownable, ReentrancyGuard {
    /// @notice App token used for entry fees and prizes
    IERC20 public immutable APP;

    /// @notice Protocol treasury address for fees
    address public protocolTreasury;

    /// @notice Burn sink address (dead address)
    address public immutable burnSink = 0x000000000000000000000000000000000000dEaD;

    /// @notice Protocol fee in basis points (e.g., 250 = 2.5%)
    uint256 public protocolFeeBps;

    /// @notice Burn fee in basis points (e.g., 100 = 1.0%)
    uint256 public burnFeeBps;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10_000;

    /// @notice Merkle root of winners (address => amount)
    bytes32 public winnersRoot;

    /// @notice Whether tournament has been finalized
    bool public finalized;

    /// @notice Tournament start time (0 = open immediately)
    uint64 public startTime;

    /// @notice Tournament end time (0 = no end)
    uint64 public endTime;

    /// @notice Entry fee per participant
    uint256 public entryFee;

    /// @notice Total prize pool (becomes net pool after finalize)
    uint256 public pool;

    /// @notice Whether an address has entered
    mapping(address => bool) public entered;

    /// @notice Whether an address has claimed their prize
    mapping(address => bool) public claimed;

    event Entered(address indexed user, uint256 fee);
    event Finalized(bytes32 winnersRoot, uint256 netPool, uint256 protocolFee, uint256 burned);
    event Claimed(address indexed user, uint256 amount);
    event FeesSet(uint256 protocolFeeBps, uint256 burnFeeBps);
    event WindowSet(uint64 startTime, uint64 endTime);
    event EntryFeeSet(uint256 entryFee);

    error AlreadyEntered();
    error TournamentNotStarted();
    error TournamentEnded();
    error AlreadyFinalized();
    error NotFinalized();
    error AlreadyClaimed();
    error InvalidProof();
    error FeesTooHigh();
    error InvalidWindow();

    /**
     * @notice Initialize tournament
     * @param appToken App token address
     * @param owner_ Tournament owner
     * @param protocolTreasury_ Protocol treasury address
     * @param entryFee_ Entry fee amount
     * @param start_ Start time (0 = immediate)
     * @param end_ End time (0 = no end)
     * @param protocolFeeBps_ Protocol fee in bps
     * @param burnFeeBps_ Burn fee in bps
     */
    constructor(
        address appToken,
        address owner_,
        address protocolTreasury_,
        uint256 entryFee_,
        uint64 start_,
        uint64 end_,
        uint256 protocolFeeBps_,
        uint256 burnFeeBps_
    ) Ownable(owner_) {
        if (end_ != 0 && end_ <= start_) revert InvalidWindow();

        APP = IERC20(appToken);
        protocolTreasury = protocolTreasury_;
        entryFee = entryFee_;
        startTime = start_;
        endTime = end_;

        _setFees(protocolFeeBps_, burnFeeBps_);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN FUNCTIONS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Set protocol and burn fees
     * @param protocolBps Protocol fee in basis points
     * @param burnBps Burn fee in basis points
     */
    function setFees(uint256 protocolBps, uint256 burnBps) external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        _setFees(protocolBps, burnBps);
    }

    function _setFees(uint256 protocolBps, uint256 burnBps) private {
        if (protocolBps + burnBps > 1500) revert FeesTooHigh(); // max 15%
        protocolFeeBps = protocolBps;
        burnFeeBps = burnBps;
        emit FeesSet(protocolBps, burnBps);
    }

    /**
     * @notice Set tournament time window
     * @param start_ Start time
     * @param end_ End time
     */
    function setWindow(uint64 start_, uint64 end_) external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        if (end_ != 0 && end_ <= start_) revert InvalidWindow();
        startTime = start_;
        endTime = end_;
        emit WindowSet(start_, end_);
    }

    /**
     * @notice Set entry fee
     * @param fee New entry fee
     */
    function setEntryFee(uint256 fee) external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        entryFee = fee;
        emit EntryFeeSet(fee);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PARTICIPANT FUNCTIONS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Enter tournament by paying entry fee
     * @dev User must approve this contract for APP tokens first
     */
    function enter() external nonReentrant {
        if (entered[msg.sender]) revert AlreadyEntered();
        if (startTime != 0 && block.timestamp < startTime) {
            revert TournamentNotStarted();
        }
        if (endTime != 0 && block.timestamp > endTime) {
            revert TournamentEnded();
        }

        entered[msg.sender] = true;
        APP.transferFrom(msg.sender, address(this), entryFee);
        pool += entryFee;

        emit Entered(msg.sender, entryFee);
    }

    /**
     * @notice Finalize tournament with winners Merkle root
     * @dev Applies protocol and burn fees, sets net pool
     * @param winnersRoot_ Merkle root of (address, amount) pairs
     */
    function finalize(bytes32 winnersRoot_) external onlyOwner nonReentrant {
        if (finalized) revert AlreadyFinalized();
        finalized = true;

        uint256 protocolFee = (pool * protocolFeeBps) / BPS;
        uint256 burnAmt = (pool * burnFeeBps) / BPS;
        uint256 netPool = pool - protocolFee - burnAmt;

        // Transfer fees
        if (protocolFee > 0) {
            APP.transfer(protocolTreasury, protocolFee);
        }
        if (burnAmt > 0) {
            APP.transfer(burnSink, burnAmt);
        }

        winnersRoot = winnersRoot_;
        pool = netPool;

        emit Finalized(winnersRoot_, netPool, protocolFee, burnAmt);
    }

    /**
     * @notice Claim prize as a winner
     * @param proof Merkle proof of (msg.sender, amount)
     * @param amount Prize amount to claim
     */
    function claim(bytes32[] calldata proof, uint256 amount) external nonReentrant {
        if (!finalized) revert NotFinalized();
        if (claimed[msg.sender]) revert AlreadyClaimed();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!MerkleProof.verify(proof, winnersRoot, leaf)) {
            revert InvalidProof();
        }

        claimed[msg.sender] = true;
        APP.transfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ENHANCED VIEW FUNCTIONS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get comprehensive tournament state
     * @return isFinalized Whether tournament is finalized
     * @return isActive Whether tournament is currently active
     * @return currentPool Current prize pool
     * @return entryFeeAmount Entry fee amount
     * @return protocolFee Protocol fee in bps
     * @return burnFee Burn fee in bps
     * @return start Start time
     * @return end End time
     */
    function getTournamentState()
        external
        view
        returns (
            bool isFinalized,
            bool isActive,
            uint256 currentPool,
            uint256 entryFeeAmount,
            uint256 protocolFee,
            uint256 burnFee,
            uint64 start,
            uint64 end
        )
    {
        isFinalized = finalized;
        isActive = !finalized && (startTime == 0 || block.timestamp >= startTime)
            && (endTime == 0 || block.timestamp <= endTime);
        currentPool = pool;
        entryFeeAmount = entryFee;
        protocolFee = protocolFeeBps;
        burnFee = burnFeeBps;
        start = startTime;
        end = endTime;
    }

    /**
     * @notice Check if user can enter tournament
     * @param user User address
     * @return canEnter Whether user can enter
     * @return reason Reason code (0=can enter, 1=already entered, 2=not started, 3=ended, 4=finalized)
     */
    function checkEntryEligibility(address user)
        external
        view
        returns (bool canEnter, uint8 reason)
    {
        if (entered[user]) return (false, 1);
        if (finalized) return (false, 4);
        if (startTime != 0 && block.timestamp < startTime) return (false, 2);
        if (endTime != 0 && block.timestamp > endTime) return (false, 3);
        return (true, 0);
    }

    /**
     * @notice Calculate fees for current pool
     * @return protocolAmount Protocol fee amount
     * @return burnAmount Burn fee amount
     * @return netAmount Net pool for winners
     */
    function calculateFees()
        external
        view
        returns (uint256 protocolAmount, uint256 burnAmount, uint256 netAmount)
    {
        protocolAmount = (pool * protocolFeeBps) / BPS;
        burnAmount = (pool * burnFeeBps) / BPS;
        netAmount = pool - protocolAmount - burnAmount;
    }
}
