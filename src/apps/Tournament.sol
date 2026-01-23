// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice Interface for FeeCollector
interface IFeeCollector {
    function depositElta(uint256 appId, uint256 amount) external;
    function depositAppToken(uint256 appId, address token, uint256 amount) external;
}

/// @notice Supported entry token types
enum EntryTokenType {
    APP, // App token (default)
    ELTA, // ELTA token
    USDC // USDC stablecoin
}

/**
 * @title Tournament
 * @author Elata Protocol
 * @notice Entry-fee tournaments with multi-currency support and FeeCollector integration
 * @dev On-chain paid competitions with transparent payouts
 *
 * Key Features:
 * - Entry fee pool accumulation
 * - Multi-currency support (APP, ELTA, USDC)
 * - Protocol fee routing to FeeCollector
 * - Burn fee for deflationary pressure
 * - Merkle proof winner claims
 * - One-time finalization
 *
 * Tournament Flow:
 * 1. Deploy tournament with parameters
 * 2. Users enter during time window (pay entry fee in selected currency)
 * 3. Owner finalizes with Merkle root of winners
 * 4. Winners claim rewards with proofs
 */
contract Tournament is AccessControl, ReentrancyGuard {
    /// @notice Module admin role - can manage settings and withdraw
    bytes32 public constant MODULE_ADMIN_ROLE = keccak256("MODULE_ADMIN_ROLE");

    /// @notice Module operator role - can manage day-to-day operations
    bytes32 public constant MODULE_OPERATOR_ROLE = keccak256("MODULE_OPERATOR_ROLE");

    /// @notice Entry token (APP, ELTA, or USDC)
    IERC20 public immutable entryToken;

    /// @notice Type of entry token
    EntryTokenType public immutable entryTokenType;

    /// @notice App ID for fee routing
    uint256 public immutable appId;

    /// @notice FeeCollector for routing protocol fees
    address public feeCollector;

    /// @notice Legacy: Protocol treasury address (fallback or USDC direct)
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
     * @param token_ Entry token address
     * @param tokenType_ Entry token type (APP, ELTA, USDC)
     * @param appId_ App ID for fee routing
     * @param admin_ Tournament admin (receives MODULE_ADMIN_ROLE and MODULE_OPERATOR_ROLE)
     * @param feeCollector_ FeeCollector address (can be address(0) for legacy)
     * @param protocolTreasury_ Protocol treasury address (fallback or USDC direct)
     * @param entryFee_ Entry fee amount
     * @param start_ Start time (0 = immediate)
     * @param end_ End time (0 = no end)
     * @param protocolFeeBps_ Protocol fee in bps
     * @param burnFeeBps_ Burn fee in bps
     */
    constructor(
        address token_,
        EntryTokenType tokenType_,
        uint256 appId_,
        address admin_,
        address feeCollector_,
        address protocolTreasury_,
        uint256 entryFee_,
        uint64 start_,
        uint64 end_,
        uint256 protocolFeeBps_,
        uint256 burnFeeBps_
    ) {
        if (end_ != 0 && end_ <= start_) revert InvalidWindow();

        entryToken = IERC20(token_);
        entryTokenType = tokenType_;
        appId = appId_;
        feeCollector = feeCollector_;
        protocolTreasury = protocolTreasury_;
        entryFee = entryFee_;
        startTime = start_;
        endTime = end_;

        // Grant roles to admin
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MODULE_ADMIN_ROLE, admin_);
        _grantRole(MODULE_OPERATOR_ROLE, admin_);

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
    function setFees(uint256 protocolBps, uint256 burnBps) external onlyRole(MODULE_OPERATOR_ROLE) {
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
    function setWindow(uint64 start_, uint64 end_) external onlyRole(MODULE_OPERATOR_ROLE) {
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
    function setEntryFee(uint256 fee) external onlyRole(MODULE_OPERATOR_ROLE) {
        if (finalized) revert AlreadyFinalized();
        entryFee = fee;
        emit EntryFeeSet(fee);
    }

    /**
     * @notice Set fee collector address
     * @param feeCollector_ New fee collector address
     */
    function setFeeCollector(address feeCollector_) external onlyRole(MODULE_ADMIN_ROLE) {
        if (finalized) revert AlreadyFinalized();
        feeCollector = feeCollector_;
    }

    // ────────────────────────────────────────────────────────────────────────────
    // PARTICIPANT FUNCTIONS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Enter tournament by paying entry fee
     * @dev User must approve this contract for entry tokens first
     */
    function enter() external nonReentrant {
        if (entered[msg.sender]) revert AlreadyEntered();
        if (startTime != 0 && block.timestamp < startTime) revert TournamentNotStarted();
        if (endTime != 0 && block.timestamp > endTime) revert TournamentEnded();

        entered[msg.sender] = true;
        entryToken.transferFrom(msg.sender, address(this), entryFee);
        pool += entryFee;

        emit Entered(msg.sender, entryFee);
    }

    /**
     * @notice Finalize tournament with winners Merkle root
     * @dev Applies protocol and burn fees, routes fees to FeeCollector
     * @param winnersRoot_ Merkle root of (address, amount) pairs
     */
    function finalize(bytes32 winnersRoot_) external onlyRole(MODULE_OPERATOR_ROLE) nonReentrant {
        if (finalized) revert AlreadyFinalized();
        finalized = true;

        uint256 protocolFee = (pool * protocolFeeBps) / BPS;
        uint256 burnAmt = (pool * burnFeeBps) / BPS;
        uint256 netPool = pool - protocolFee - burnAmt;

        // Route protocol fees based on token type
        if (protocolFee > 0) {
            _routeProtocolFees(protocolFee);
        }

        // Burn tokens (all token types support burn sink)
        if (burnAmt > 0) {
            entryToken.transfer(burnSink, burnAmt);
        }

        winnersRoot = winnersRoot_;
        pool = netPool;

        emit Finalized(winnersRoot_, netPool, protocolFee, burnAmt);
    }

    /**
     * @dev Route protocol fees to FeeCollector or treasury
     */
    function _routeProtocolFees(uint256 amount) internal {
        if (feeCollector != address(0)) {
            // Route to FeeCollector based on token type
            entryToken.approve(feeCollector, amount);

            if (entryTokenType == EntryTokenType.ELTA) {
                IFeeCollector(feeCollector).depositElta(appId, amount);
            } else if (entryTokenType == EntryTokenType.APP) {
                IFeeCollector(feeCollector).depositAppToken(appId, address(entryToken), amount);
            } else {
                // USDC goes directly to treasury
                entryToken.transfer(protocolTreasury, amount);
            }
        } else {
            // Fallback: send directly to treasury
            entryToken.transfer(protocolTreasury, amount);
        }
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
        if (!MerkleProof.verify(proof, winnersRoot, leaf)) revert InvalidProof();

        claimed[msg.sender] = true;
        entryToken.transfer(msg.sender, amount);

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
     * @return reason Reason code (0=can enter, 1=already entered, 2=not started, 3=ended,
     * 4=finalized)
     */
    function checkEntryEligibility(address user) external view returns (bool canEnter, uint8 reason) {
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
    function calculateFees() external view returns (uint256 protocolAmount, uint256 burnAmount, uint256 netAmount) {
        protocolAmount = (pool * protocolFeeBps) / BPS;
        burnAmount = (pool * burnFeeBps) / BPS;
        netAmount = pool - protocolAmount - burnAmount;
    }
}
