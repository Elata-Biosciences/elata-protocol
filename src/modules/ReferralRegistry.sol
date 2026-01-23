// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ReferralRegistry
 * @author Elata Biosciences
 * @notice Tracks referrals and distributes ELTA rewards to referrers
 * @dev Per-app referral tracking with one-time binding
 *
 * Per Protocol Changes document section 14:
 * - Referrals apply to bonding curve buys
 * - referrerOf[buyer] stored once (one-time binding)
 * - Pay referral from existing fee split (not inflation)
 * - referralBps out of the existing fee
 *
 * Key Features:
 * - Per-app referrer binding (one buyer can have different referrers per app)
 * - One-time binding per app (first referrer wins)
 * - Rewards accrue in ELTA, claimable anytime
 * - No self-referral
 * - Authorized callers (bonding curves) set referrers
 *
 * Security:
 * - ReentrancyGuard on claims
 * - Authorized caller whitelist
 * - BPS cap to prevent excessive referral fees
 */
contract ReferralRegistry is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error SelfReferral();
    error BpsTooHigh();
    error Unauthorized();

    // =========== Events ===========
    event ReferrerSet(uint256 indexed appId, address indexed buyer, address indexed referrer);
    event RewardAccrued(uint256 indexed appId, address indexed referrer, address indexed buyer, uint256 amount);
    event RewardsClaimed(address indexed referrer, uint256 amount);
    event ReferralBpsUpdated(uint256 oldBps, uint256 newBps);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    // =========== Constants ===========

    /// @notice Maximum referral fee (20%)
    uint256 public constant MAX_REFERRAL_BPS = 2000;

    /// @notice Basis points denominator
    uint256 public constant BPS = 10000;

    // =========== State ===========

    /// @notice Admin address
    address public admin;

    /// @notice ELTA token for rewards
    IERC20 public immutable elta;

    /// @notice Referral fee in basis points
    uint256 public referralBps;

    /// @notice Authorized callers (bonding curves) who can set referrers
    mapping(address => bool) public authorizedCallers;

    /// @notice Referrer for each (appId, buyer) pair
    mapping(uint256 => mapping(address => address)) private _referrers;

    /// @notice Referral count per (appId, referrer)
    mapping(uint256 => mapping(address => uint256)) private _referralCounts;

    /// @notice Pending ELTA rewards per referrer
    mapping(address => uint256) public pendingRewards;

    /// @notice Total ELTA earned per referrer (historical)
    mapping(address => uint256) public totalEarned;

    // =========== Constructor ===========

    /**
     * @notice Create a new referral registry
     * @param _admin Admin address
     * @param _elta ELTA token address
     * @param _referralBps Initial referral fee in basis points
     */
    constructor(address _admin, address _elta, uint256 _referralBps) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_elta == address(0)) revert ZeroAddress();
        if (_referralBps > MAX_REFERRAL_BPS) revert BpsTooHigh();

        admin = _admin;
        elta = IERC20(_elta);
        referralBps = _referralBps;
    }

    // =========== Modifiers ===========

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender]) revert Unauthorized();
        _;
    }

    // =========== Referral Functions ===========

    /**
     * @notice Set referrer for a buyer (one-time binding per app)
     * @param _appId App ID
     * @param _buyer Buyer address
     * @param _referrer Referrer address
     * @dev Called by bonding curve on first buy with referrer
     */
    function setReferrer(uint256 _appId, address _buyer, address _referrer) external onlyAuthorized {
        if (_referrer == address(0)) revert ZeroAddress();
        if (_buyer == _referrer) revert SelfReferral();

        // One-time binding: if already set, ignore
        if (_referrers[_appId][_buyer] != address(0)) {
            return;
        }

        _referrers[_appId][_buyer] = _referrer;
        _referralCounts[_appId][_referrer]++;

        emit ReferrerSet(_appId, _buyer, _referrer);
    }

    /**
     * @notice Accrue referral reward from a fee
     * @param _appId App ID
     * @param _buyer Buyer whose referrer gets reward
     * @param _feeAmount Total fee amount from which referral is calculated
     * @dev Called by fee pipeline when processing fees
     */
    function accrueReferralReward(uint256 _appId, address _buyer, uint256 _feeAmount) external onlyAuthorized {
        address referrer = _referrers[_appId][_buyer];
        if (referrer == address(0)) {
            // No referrer, no reward
            return;
        }

        uint256 reward = (_feeAmount * referralBps) / BPS;
        if (reward == 0) return;

        pendingRewards[referrer] += reward;
        totalEarned[referrer] += reward;

        emit RewardAccrued(_appId, referrer, _buyer, reward);
    }

    /**
     * @notice Claim pending referral rewards
     * @dev Transfers all pending ELTA rewards to caller
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        if (amount == 0) return;

        pendingRewards[msg.sender] = 0;
        elta.safeTransfer(msg.sender, amount);

        emit RewardsClaimed(msg.sender, amount);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Set referral fee percentage
     * @param _referralBps New referral fee in basis points
     */
    function setReferralBps(uint256 _referralBps) external onlyAdmin {
        if (_referralBps > MAX_REFERRAL_BPS) revert BpsTooHigh();

        uint256 oldBps = referralBps;
        referralBps = _referralBps;

        emit ReferralBpsUpdated(oldBps, _referralBps);
    }

    /**
     * @notice Set authorized caller status
     * @param _caller Caller address
     * @param _authorized Whether caller is authorized
     */
    function setAuthorizedCaller(address _caller, bool _authorized) external onlyAdmin {
        authorizedCallers[_caller] = _authorized;
        emit AuthorizedCallerUpdated(_caller, _authorized);
    }

    /**
     * @notice Transfer admin role
     * @param _admin New admin address
     */
    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin = _admin;
        emit AdminUpdated(oldAdmin, _admin);
    }

    // =========== View Functions ===========

    /**
     * @notice Get referrer for a buyer in an app
     * @param _appId App ID
     * @param _buyer Buyer address
     * @return Referrer address (0 if none)
     */
    function getReferrer(uint256 _appId, address _buyer) external view returns (address) {
        return _referrers[_appId][_buyer];
    }

    /**
     * @notice Get number of referrals for a referrer in an app
     * @param _appId App ID
     * @param _referrer Referrer address
     * @return Number of referrals
     */
    function getReferralCount(uint256 _appId, address _referrer) external view returns (uint256) {
        return _referralCounts[_appId][_referrer];
    }
}
