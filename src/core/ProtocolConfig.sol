// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProtocolConfig
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Centralized configuration store for all protocol parameters.
 * @dev Parameters are bounded and emit events on change. Critical values (fees, splits, targets) require
 *      timelock authorization; operational values (slippage, router allowlist) are admin-controlled.
 *      Fee BPS values must sum to 10000 (100%).
 */
contract ProtocolConfig {
    // =========== Errors ===========
    error ZeroAddress();
    error OnlyTimelock();
    error OnlyAdmin();
    error ExceedsMaxBound();
    error BelowMinBound();
    error InvalidFeeSplits();
    error InvalidBound();

    // =========== Events ===========
    event AppCreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event AppCreationSeedUpdated(uint256 oldSeed, uint256 newSeed);
    event BondingCurveTaxUpdated(uint256 oldBps, uint256 newBps);
    event GraduationTargetUpdated(uint256 oldTarget, uint256 newTarget);
    event LpLockDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event ActivationDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event MaxCurveDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event AppTransferTaxUpdated(uint256 oldBps, uint256 newBps);
    event MaxAppTransferTaxUpdated(uint256 oldMax, uint256 newMax);
    event FeeSplitsUpdated(uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury, uint256 referral);
    event EpochLengthUpdated(uint256 oldLength, uint256 newLength);
    event MaxSlippageUpdated(uint256 oldBps, uint256 newBps);
    event RouterAllowlisted(address indexed router, bool allowed);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event MinSwapThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // =========== Constants (Bounds) ===========
    // App creation bounds
    uint256 public constant MAX_APP_CREATION_FEE = 1000 ether;

    // Tax bounds (BPS)
    uint256 public constant MAX_BONDING_CURVE_TAX_BPS = 500; // 5%
    uint256 public constant MAX_TRANSFER_TAX_BPS = 1000; // 10% absolute max
    uint256 public constant MAX_SNIPER_FEE_BPS = 1000; // 10% max sniper protection fee

    // Graduation bounds
    uint256 public constant MIN_GRADUATION_TARGET = 1000 ether;
    uint256 public constant MAX_GRADUATION_TARGET = 1_000_000 ether;

    // LP lock bounds
    uint256 public constant MIN_LP_LOCK_DURATION = 30 days;
    uint256 public constant MAX_LP_LOCK_DURATION = 5 * 365 days;

    // Fee split bounds (per bucket)
    uint256 public constant MAX_BUCKET_BPS = 9000; // 90% max per bucket

    // Epoch bounds
    uint256 public constant MIN_EPOCH_LENGTH = 1 hours;
    uint256 public constant MAX_EPOCH_LENGTH = 7 days;

    // Slippage bounds
    uint256 public constant MAX_SLIPPAGE_BPS = 1000; // 10%

    // Swap threshold bounds
    uint256 public constant MIN_SWAP_THRESHOLD_MAX = 1000 ether; // Max value for minSwapThreshold

    // Curve lifecycle bounds
    uint256 public constant MIN_ACTIVATION_DELAY = 0;
    uint256 public constant MAX_ACTIVATION_DELAY = 24 hours;
    uint256 public constant MIN_CURVE_DURATION = 7 days;
    uint256 public constant MAX_CURVE_DURATION = 90 days;

    // =========== State ===========
    address public admin;
    address public timelock;
    address public treasury;

    // App creation
    uint256 public appCreationFeeElta;
    uint256 public appCreationSeedElta;

    // Bonding curve
    uint256 public bondingCurveTradeTaxBps;
    uint256 public graduationTarget;
    uint256 public lpLockDuration;
    uint256 public activationDelay;
    uint256 public maxCurveDuration;

    // App transfer tax
    uint256 public appTransferTaxBps;
    uint256 public maxAppTransferTaxBps;

    // Fee splits (must sum to 10000)
    struct FeeSplit {
        uint256 appStakersBps;
        uint256 veEltaBps;
        uint256 creatorBps;
        uint256 treasuryBps;
        uint256 referralBps;
    }

    FeeSplit internal _feeSplits;

    // Settlement
    uint256 public epochLength;
    uint256 public maxSlippageBps;
    uint256 public minSwapThreshold;

    // Router allowlist
    mapping(address => bool) internal _routerAllowed;
    address[] internal _allowedRouters;

    // =========== Modifiers ===========
    modifier onlyTimelock() {
        if (msg.sender != timelock) revert OnlyTimelock();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    // =========== Constructor ===========
    constructor(address _admin, address _timelock) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_timelock == address(0)) revert ZeroAddress();

        admin = _admin;
        timelock = _timelock;
        treasury = _admin; // Default treasury to admin, should be updated

        // Set defaults
        _setDefaults();
    }

    function _setDefaults() internal {
        // App creation defaults
        appCreationFeeElta = 10 ether;
        appCreationSeedElta = 100 ether;

        // Bonding curve defaults
        bondingCurveTradeTaxBps = 100; // 1%
        graduationTarget = 42_000 ether;
        lpLockDuration = 365 days * 2; // 2 years
        activationDelay = 1 hours; // 1 hour delay before curve becomes active
        maxCurveDuration = 30 days; // 30 days max before forced graduation

        // App transfer tax defaults
        appTransferTaxBps = 100; // 1%
        maxAppTransferTaxBps = 500; // 5%

        // Fee splits defaults (must sum to 10000)
        _feeSplits = FeeSplit({
            appStakersBps: 7000, // 70%
            veEltaBps: 1500, // 15%
            creatorBps: 500, // 5%
            treasuryBps: 1000, // 10%
            referralBps: 0 // 0%
        });

        // Settlement defaults
        epochLength = 1 days;
        maxSlippageBps = 500; // 5%
        minSwapThreshold = 1 ether; // Minimum amount to swap
    }

    // =========== View Functions ===========

    function feeSplits()
        external
        view
        returns (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury_, uint256 referral)
    {
        return (
            _feeSplits.appStakersBps,
            _feeSplits.veEltaBps,
            _feeSplits.creatorBps,
            _feeSplits.treasuryBps,
            _feeSplits.referralBps
        );
    }

    function isRouterAllowed(address router) external view returns (bool) {
        return _routerAllowed[router];
    }

    function getAllowedRouters() external view returns (address[] memory) {
        return _allowedRouters;
    }

    // =========== Timelock-Only Setters (Critical Parameters) ===========

    function setAppCreationFeeElta(uint256 newFee) external onlyTimelock {
        if (newFee > MAX_APP_CREATION_FEE) revert ExceedsMaxBound();
        uint256 oldFee = appCreationFeeElta;
        appCreationFeeElta = newFee;
        emit AppCreationFeeUpdated(oldFee, newFee);
    }

    function setAppCreationSeedElta(uint256 newSeed) external onlyTimelock {
        uint256 oldSeed = appCreationSeedElta;
        appCreationSeedElta = newSeed;
        emit AppCreationSeedUpdated(oldSeed, newSeed);
    }

    function setBondingCurveTradeTaxBps(uint256 newBps) external onlyTimelock {
        if (newBps > MAX_BONDING_CURVE_TAX_BPS) revert ExceedsMaxBound();
        uint256 oldBps = bondingCurveTradeTaxBps;
        bondingCurveTradeTaxBps = newBps;
        emit BondingCurveTaxUpdated(oldBps, newBps);
    }

    function setGraduationTarget(uint256 newTarget) external onlyTimelock {
        if (newTarget < MIN_GRADUATION_TARGET) revert BelowMinBound();
        if (newTarget > MAX_GRADUATION_TARGET) revert ExceedsMaxBound();
        uint256 oldTarget = graduationTarget;
        graduationTarget = newTarget;
        emit GraduationTargetUpdated(oldTarget, newTarget);
    }

    function setLpLockDuration(uint256 newDuration) external onlyTimelock {
        if (newDuration < MIN_LP_LOCK_DURATION) revert BelowMinBound();
        if (newDuration > MAX_LP_LOCK_DURATION) revert ExceedsMaxBound();
        uint256 oldDuration = lpLockDuration;
        lpLockDuration = newDuration;
        emit LpLockDurationUpdated(oldDuration, newDuration);
    }

    function setActivationDelay(uint256 newDelay) external onlyTimelock {
        if (newDelay > MAX_ACTIVATION_DELAY) revert ExceedsMaxBound();
        uint256 oldDelay = activationDelay;
        activationDelay = newDelay;
        emit ActivationDelayUpdated(oldDelay, newDelay);
    }

    function setMaxCurveDuration(uint256 newDuration) external onlyTimelock {
        if (newDuration < MIN_CURVE_DURATION) revert BelowMinBound();
        if (newDuration > MAX_CURVE_DURATION) revert ExceedsMaxBound();
        uint256 oldDuration = maxCurveDuration;
        maxCurveDuration = newDuration;
        emit MaxCurveDurationUpdated(oldDuration, newDuration);
    }

    function setAppTransferTaxBps(uint256 newBps) external onlyTimelock {
        if (newBps > maxAppTransferTaxBps) revert ExceedsMaxBound();
        uint256 oldBps = appTransferTaxBps;
        appTransferTaxBps = newBps;
        emit AppTransferTaxUpdated(oldBps, newBps);
    }

    function setMaxAppTransferTaxBps(uint256 newMax) external onlyTimelock {
        if (newMax > MAX_TRANSFER_TAX_BPS) revert ExceedsMaxBound();
        if (newMax < appTransferTaxBps) revert InvalidBound();
        uint256 oldMax = maxAppTransferTaxBps;
        maxAppTransferTaxBps = newMax;
        emit MaxAppTransferTaxUpdated(oldMax, newMax);
    }

    function setFeeSplits(uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury_, uint256 referral)
        external
        onlyTimelock
    {
        // Check sum equals 10000
        if (appStakers + veElta + creator + treasury_ + referral != 10000) {
            revert InvalidFeeSplits();
        }

        // Check individual bounds
        if (appStakers > MAX_BUCKET_BPS) revert ExceedsMaxBound();
        if (veElta > MAX_BUCKET_BPS) revert ExceedsMaxBound();
        if (creator > MAX_BUCKET_BPS) revert ExceedsMaxBound();
        if (treasury_ > MAX_BUCKET_BPS) revert ExceedsMaxBound();
        if (referral > MAX_BUCKET_BPS) revert ExceedsMaxBound();

        _feeSplits = FeeSplit({
            appStakersBps: appStakers,
            veEltaBps: veElta,
            creatorBps: creator,
            treasuryBps: treasury_,
            referralBps: referral
        });

        emit FeeSplitsUpdated(appStakers, veElta, creator, treasury_, referral);
    }

    function setEpochLength(uint256 newLength) external onlyTimelock {
        if (newLength < MIN_EPOCH_LENGTH) revert BelowMinBound();
        if (newLength > MAX_EPOCH_LENGTH) revert ExceedsMaxBound();
        uint256 oldLength = epochLength;
        epochLength = newLength;
        emit EpochLengthUpdated(oldLength, newLength);
    }

    function setTreasury(address newTreasury) external onlyTimelock {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    // =========== Admin-Only Setters (Operational Parameters) ===========

    function setMaxSlippageBps(uint256 newBps) external onlyAdmin {
        if (newBps > MAX_SLIPPAGE_BPS) revert ExceedsMaxBound();
        uint256 oldBps = maxSlippageBps;
        maxSlippageBps = newBps;
        emit MaxSlippageUpdated(oldBps, newBps);
    }

    function setMinSwapThreshold(uint256 newThreshold) external onlyTimelock {
        if (newThreshold > MIN_SWAP_THRESHOLD_MAX) revert ExceedsMaxBound();
        uint256 oldThreshold = minSwapThreshold;
        minSwapThreshold = newThreshold;
        emit MinSwapThresholdUpdated(oldThreshold, newThreshold);
    }

    function setRouterAllowed(address router, bool allowed) external onlyAdmin {
        if (router == address(0)) revert ZeroAddress();

        bool wasAllowed = _routerAllowed[router];
        _routerAllowed[router] = allowed;

        // Update array
        if (allowed && !wasAllowed) {
            _allowedRouters.push(router);
        } else if (!allowed && wasAllowed) {
            _removeFromArray(router);
        }

        emit RouterAllowlisted(router, allowed);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminTransferred(oldAdmin, newAdmin);
    }

    // =========== Internal ===========

    function _removeFromArray(address router) internal {
        uint256 length = _allowedRouters.length;
        for (uint256 i = 0; i < length; i++) {
            if (_allowedRouters[i] == router) {
                _allowedRouters[i] = _allowedRouters[length - 1];
                _allowedRouters.pop();
                break;
            }
        }
    }
}
