// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAppFeeRouter} from "../interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../interfaces/IElataPoints.sol";
import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";
import {AppToken} from "./AppToken.sol";
import {LpLocker} from "./LpLocker.sol";
import {FeeKind} from "../fees/FeeKind.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAppFactory {
    function onAppGraduated(
        uint256 appId,
        address pair,
        address locker,
        uint256 unlockAt,
        uint256 totalRaisedElta,
        uint256 tokensLeft
    ) external;
}

interface IFeeCollector {
    function depositElta(uint256 appId, FeeKind kind, uint256 amount) external;
}

/**
 * @title AppBondingCurve
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Constant-product bonding curve for fair app token distribution.
 * @dev Implements x*y=k pricing where buyers exchange ELTA for app tokens along a deterministic
 *      curve. The creator seeds initial liquidity; price increases with each purchase until the
 *      graduation threshold is reached. Upon graduation, remaining tokens and accumulated ELTA
 *      form a Uniswap LP pair with the LP tokens locked for a fixed duration. Includes slippage
 *      bounds and refund logic for purchases that exceed available supply.
 */
contract AppBondingCurve is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Enums ===========

    /// @notice Curve lifecycle states
    enum CurveState {
        PENDING, // Created, not yet active
        ACTIVE, // Buy enabled
        GRADUATED, // LP created, curve closed
        CANCELLED // Creator cancelled before activation
    }

    // Core assets
    IERC20 public immutable ELTA;
    AppToken public immutable TOKEN;
    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable uniFactory;

    // Factory and identification
    address public immutable appFactory;
    uint256 public immutable appId;

    // Curve state
    uint256 public reserveElta; // x in constant product
    uint256 public reserveToken; // y in constant product
    uint256 public immutable targetRaisedElta;
    uint256 public immutable initialK; // k = x * y at start
    bool public graduated;

    // Lifecycle state
    CurveState public state;
    uint256 public activationTime; // When curve becomes ACTIVE
    uint256 public deadline; // When forced graduation can happen

    // Fee accumulation for FeeCollector
    uint256 public pendingFees;
    address public feeCollector;

    // ReferralRegistry removed; kept as unused storage slot for upgrade-safety in tests/scripts.
    address public referralRegistry;

    // Post-graduation data
    address public pair;
    address public locker;
    uint256 public lpUnlockAt;

    // Configuration
    uint256 public immutable lpLockDuration;
    address public immutable lpBeneficiary;
    address public immutable treasury;
    IAppFeeRouter public immutable appFeeRouter; // Fee router for protocol revenues

    // XP gating configuration
    IElataPoints public immutable elataPoints;
    uint256 public immutable launchTimestamp;
    uint256 public xpMinForEarlyBuy = 100e18; // governance-configurable (default 100 XP)
    uint256 public earlyBuyDuration = 6 hours; // governance-configurable (default 6 hours)
    address public governance;

    // Sniper protection configuration
    uint256 public sniperFeeBps = 500; // 5% extra fee during early window
    uint256 public sniperFeeDuration = 1 hours; // Duration of elevated fees
    bool public sniperFeeEnabled = false; // Governance can enable
    uint256 public constant MAX_SNIPER_FEE_BPS = 1000; // 10% max

    // Creator address (for cancel functionality)
    address public immutable creator;

    // Events
    event CurveInitialized(uint256 indexed appId, uint256 seedElta, uint256 tokenSupply, uint256 initialK);
    event XPGateUpdated(uint256 minXP, uint256 duration);
    event SniperFeeConfigUpdated(uint256 feeBps, uint256 duration, bool enabled);
    event TokensPurchased(
        uint256 indexed appId,
        address indexed buyer,
        uint256 eltaIn,
        uint256 tokensOut,
        uint256 newReserveElta,
        uint256 newReserveToken,
        uint256 newPrice
    );
    event AppGraduated(
        uint256 indexed appId,
        address indexed token,
        address pair,
        address locker,
        uint256 unlockAt,
        uint256 totalRaisedElta,
        uint256 tokensToLp
    );
    event StateChanged(uint256 indexed appId, CurveState oldState, CurveState newState);
    event CurveActivated(uint256 indexed appId, uint256 activationTime, uint256 deadline);
    event CurveCancelled(uint256 indexed appId, uint256 eltaRefunded, uint256 tokensRefunded);
    event ForceGraduated(uint256 indexed appId, uint256 eltaRaised);
    event FeesSwepted(uint256 indexed appId, uint256 amount, address indexed feeCollector);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    error AlreadyGraduated();
    error NotGraduated();
    error InsufficientOutput();
    error ZeroInput();
    error NotInitialized();
    error OnlyFactory();
    error InvalidAmount();
    error InsufficientXP();
    error OnlyGovernance();
    error NotPending();
    error NotActive();
    error TooEarlyToActivate();
    error DeadlineNotReached();
    error AlreadyCancelled();
    error OnlyCreator();
    error SniperFeeTooHigh();

    /// @notice Constructor parameters bundled to avoid stack too deep
    struct InitParams {
        uint256 appId;
        address factory;
        IERC20 elta;
        AppToken token;
        IUniswapV2Router02 router;
        uint256 targetRaisedElta;
        uint256 lpLockDuration;
        address lpBeneficiary;
        address treasury;
        IAppFeeRouter appFeeRouter;
        IElataPoints elataPoints;
        address governance;
        uint256 activationDelay;
        uint256 maxDuration;
        address creator;
        address feeCollector;
        address referralRegistry;
    }

    modifier onlyFactory() {
        if (msg.sender != appFactory) revert OnlyFactory();
        _;
    }

    modifier notGraduated() {
        if (graduated) revert AlreadyGraduated();
        _;
    }

    modifier onlyActive() {
        if (state != CurveState.ACTIVE) revert NotActive();
        _;
    }

    modifier onlyPending() {
        if (state != CurveState.PENDING) revert NotPending();
        _;
    }

    /**
     * @notice Initialize bonding curve contract
     * @param params InitParams struct containing all constructor parameters
     */
    constructor(InitParams memory params) {
        require(params.factory != address(0), "Zero factory");
        require(address(params.elta) != address(0), "Zero ELTA");
        require(address(params.token) != address(0), "Zero token");
        require(address(params.router) != address(0), "Zero router");
        require(params.targetRaisedElta > 0, "Zero target");
        require(params.lpBeneficiary != address(0), "Zero beneficiary");
        require(params.treasury != address(0), "Zero treasury");
        require(address(params.elataPoints) != address(0), "Zero Points");
        require(params.governance != address(0), "Zero governance");
        require(params.creator != address(0), "Zero creator");
        // appFeeRouter can be address(0) to disable fee forwarding

        appId = params.appId;
        appFactory = params.factory;
        ELTA = params.elta;
        TOKEN = params.token;
        router = params.router;
        uniFactory = IUniswapV2Factory(params.router.factory());
        targetRaisedElta = params.targetRaisedElta;
        lpLockDuration = params.lpLockDuration;
        lpBeneficiary = params.lpBeneficiary;
        treasury = params.treasury;
        appFeeRouter = params.appFeeRouter;
        elataPoints = params.elataPoints;
        governance = params.governance;
        launchTimestamp = block.timestamp;
        creator = params.creator;
        feeCollector = params.feeCollector;
        referralRegistry = params.referralRegistry;

        // Set lifecycle timestamps
        state = CurveState.PENDING;
        activationTime = block.timestamp + params.activationDelay;
        deadline = activationTime + params.maxDuration;
    }

    /**
     * @notice Initialize curve with seed liquidity (called once by factory)
     * @param seedElta Initial ELTA liquidity
     * @param tokenSupply Initial token supply
     */
    function initializeCurve(uint256 seedElta, uint256 tokenSupply) external onlyFactory {
        require(reserveElta == 0 && reserveToken == 0, "Already initialized");
        require(seedElta > 0 && tokenSupply > 0, "Invalid initialization");

        reserveElta = seedElta;
        reserveToken = tokenSupply;

        // Store initial k for reference
        uint256 k = seedElta * tokenSupply;
        // We can't make initialK immutable after constructor, so we emit it

        emit CurveInitialized(appId, seedElta, tokenSupply, k);
    }

    /**
     * @notice Calculate tokens received for given ELTA input
     * @param eltaIn Amount of ELTA to spend
     * @return tokensOut Amount of tokens that would be received
     */
    function getTokensOut(uint256 eltaIn) public view returns (uint256 tokensOut) {
        if (graduated || eltaIn == 0 || reserveElta == 0) return 0;

        // Constant product: x * y = k
        // newX = x + eltaIn
        // newY = k / newX
        // tokensOut = y - newY

        uint256 k = reserveElta * reserveToken;
        uint256 newReserveElta = reserveElta + eltaIn;
        uint256 newReserveToken = k / newReserveElta;

        tokensOut = reserveToken - newReserveToken;
    }

    /**
     * @notice Calculate ELTA needed for desired token amount
     * @param tokensDesired Amount of tokens desired
     * @return eltaIn Amount of ELTA needed
     */
    function getEltaInForTokens(uint256 tokensDesired) public view returns (uint256 eltaIn) {
        if (graduated || tokensDesired == 0 || tokensDesired >= reserveToken) return 0;

        // Reverse calculation: y - newY = tokensDesired
        // newY = y - tokensDesired
        // newX = k / newY
        // eltaIn = newX - x

        uint256 k = reserveElta * reserveToken;
        uint256 newReserveToken = reserveToken - tokensDesired;
        uint256 newReserveElta = k / newReserveToken;

        eltaIn = newReserveElta - reserveElta;
    }

    /**
     * @notice Get current token price in ELTA
     * @return price Current price per token (scaled by 1e18)
     */
    function getCurrentPrice() external view returns (uint256 price) {
        if (reserveToken == 0) return 0;
        // Price = marginal rate = dx/dy at current point
        // For constant product: price ≈ x/y
        price = (reserveElta * 1e18) / reserveToken;
    }

    /**
     * @notice Buy app tokens with ELTA
     * @param eltaIn Amount of ELTA to spend
     * @param minTokensOut Minimum tokens expected (slippage protection)
     * @param referrer Optional referrer address (address(0) for none)
     * @return tokensOut Actual tokens received
     */
    function buy(uint256 eltaIn, uint256 minTokensOut, address referrer)
        external
        nonReentrant
        onlyActive
        returns (uint256 tokensOut)
    {
        if (eltaIn == 0) revert ZeroInput();
        if (reserveElta == 0) revert NotInitialized();

        // ReferralRegistry removed; `referrer` is accepted for ABI/back-compat but ignored.
        referrer = referrer;

        // XP gating for early launch window
        if (block.timestamp < launchTimestamp + earlyBuyDuration) {
            if (elataPoints.balanceOf(msg.sender) < xpMinForEarlyBuy) revert InsufficientXP();
        }

        // Calculate maximum ELTA we can accept before hitting target
        uint256 remainingToTarget = targetRaisedElta > reserveElta ? targetRaisedElta - reserveElta : 0;
        uint256 actualEltaIn = eltaIn > remainingToTarget ? remainingToTarget : eltaIn;

        if (actualEltaIn == 0) revert InvalidAmount();

        // Calculate tokens out
        tokensOut = getTokensOut(actualEltaIn);
        if (tokensOut < minTokensOut) revert InsufficientOutput();

        // Calculate fee ON TOP of trade (buyer pays extra)
        uint256 tradingFee = 0;
        if (address(appFeeRouter) != address(0)) {
            uint256 effectiveFeeBps = appFeeRouter.feeBps();

            // Apply sniper fee during early window if enabled
            if (sniperFeeEnabled && block.timestamp < activationTime + sniperFeeDuration) {
                effectiveFeeBps += sniperFeeBps;
            }

            tradingFee = (actualEltaIn * effectiveFeeBps) / 10_000;
        }

        // Pull ELTA from buyer: curve amount + trading fee
        ELTA.safeTransferFrom(msg.sender, address(this), actualEltaIn + tradingFee);

        // Accumulate trading fee for later sweep to FeeCollector
        // This replaces the old appFeeRouter forwarding mechanism
        if (tradingFee > 0) {
            pendingFees += tradingFee;
        }

        // Update reserves with ELTA (no more legacy protocol fee deduction)
        reserveElta += actualEltaIn;
        reserveToken -= tokensOut;

        // Transfer tokens to buyer
        IERC20(address(TOKEN)).safeTransfer(msg.sender, tokensOut);

        // Calculate new price for event
        uint256 newPrice = reserveToken > 0 ? (reserveElta * 1e18) / reserveToken : 0;

        emit TokensPurchased(appId, msg.sender, actualEltaIn, tokensOut, reserveElta, reserveToken, newPrice);

        // Refund excess ELTA if any
        uint256 refund = eltaIn - actualEltaIn;
        if (refund > 0) ELTA.safeTransfer(msg.sender, refund);

        // Check for graduation
        if (reserveElta >= targetRaisedElta) _graduate();
    }

    /**
     * @notice Manually trigger graduation if target reached
     */
    function graduate() external nonReentrant notGraduated {
        require(reserveElta >= targetRaisedElta, "Target not reached");
        _graduate();
    }

    /**
     * @notice Get detailed curve state
     * @return eltaReserve Current ELTA reserves
     * @return tokenReserve Current token reserves
     * @return target Target ELTA to raise
     * @return isGraduated Whether curve has graduated
     * @return currentPrice Current token price
     * @return progress Progress toward graduation (basis points)
     */
    function getCurveState()
        external
        view
        returns (
            uint256 eltaReserve,
            uint256 tokenReserve,
            uint256 target,
            bool isGraduated,
            uint256 currentPrice,
            uint256 progress
        )
    {
        eltaReserve = reserveElta;
        tokenReserve = reserveToken;
        target = targetRaisedElta;
        isGraduated = graduated;
        currentPrice = tokenReserve > 0 ? (reserveElta * 1e18) / reserveToken : 0;
        progress = target > 0 ? (reserveElta * 10000) / target : 0; // basis points
    }

    /**
     * @dev Internal graduation logic
     */
    function _graduate() internal {
        CurveState oldState = state;
        state = CurveState.GRADUATED;
        graduated = true;

        emit StateChanged(appId, oldState, CurveState.GRADUATED);

        // Create or get existing pair
        address pairAddress = uniFactory.getPair(address(TOKEN), address(ELTA));
        if (pairAddress == address(0)) pairAddress = uniFactory.createPair(address(TOKEN), address(ELTA));
        pair = pairAddress;

        // Approve router for liquidity addition
        TOKEN.approve(address(router), reserveToken);
        ELTA.approve(address(router), reserveElta);

        // Add all remaining reserves as liquidity
        (,, uint256 liquidity) = router.addLiquidity(
            address(TOKEN),
            address(ELTA),
            reserveToken,
            reserveElta,
            0, // Accept any amount (price continuity guaranteed)
            0, // Accept any amount
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );

        // Create LP locker
        lpUnlockAt = block.timestamp + lpLockDuration;
        LpLocker lpLocker = new LpLocker(appId, pair, lpBeneficiary, lpUnlockAt);
        locker = address(lpLocker);

        // Transfer LP tokens to locker
        IERC20(pair).safeTransfer(address(lpLocker), liquidity);
        lpLocker.lockLp(liquidity);

        emit AppGraduated(appId, address(TOKEN), pair, locker, lpUnlockAt, reserveElta, reserveToken);

        // Notify factory
        IAppFactory(appFactory).onAppGraduated(appId, pair, locker, lpUnlockAt, reserveElta, reserveToken);

        // Clear reserves (all moved to LP)
        reserveElta = 0;
        reserveToken = 0;
    }

    /**
     * @notice Set XP gating parameters (governance only)
     * @param _minXP Minimum XP required for early access
     * @param _duration Duration of early access period in seconds
     */
    function setXPGate(uint256 _minXP, uint256 _duration) external {
        if (msg.sender != governance) revert OnlyGovernance();
        xpMinForEarlyBuy = _minXP;
        earlyBuyDuration = _duration;
        emit XPGateUpdated(_minXP, _duration);
    }

    /**
     * @notice Set sniper protection fee configuration
     * @param _feeBps Sniper fee in basis points (max 10%)
     * @param _duration Duration of elevated fees from activation
     * @param _enabled Whether sniper fee is enabled
     */
    function setSniperFeeConfig(uint256 _feeBps, uint256 _duration, bool _enabled) external {
        if (msg.sender != governance) revert OnlyGovernance();
        if (_feeBps > MAX_SNIPER_FEE_BPS) revert SniperFeeTooHigh();
        sniperFeeBps = _feeBps;
        sniperFeeDuration = _duration;
        sniperFeeEnabled = _enabled;
        emit SniperFeeConfigUpdated(_feeBps, _duration, _enabled);
    }

    /**
     * @notice Check if a user can buy tokens
     * @param user User address to check
     * @return canBuy Whether the user can buy
     */
    function canUserBuy(address user) external view returns (bool canBuy) {
        if (graduated) return false;
        if (block.timestamp >= launchTimestamp + earlyBuyDuration) return true;
        return elataPoints.balanceOf(user) >= xpMinForEarlyBuy;
    }

    /**
     * @notice Get early access information
     * @return launchTime App launch timestamp
     * @return duration Early access duration in seconds
     * @return xpMin Minimum XP required
     * @return isActive Whether early access is currently active
     */
    function getEarlyAccessInfo()
        external
        view
        returns (uint256 launchTime, uint256 duration, uint256 xpMin, bool isActive)
    {
        launchTime = launchTimestamp;
        duration = earlyBuyDuration;
        xpMin = xpMinForEarlyBuy;
        isActive = block.timestamp < launchTimestamp + duration;
    }

    // =========== Lifecycle Functions ===========

    /**
     * @notice Activate the curve after activation delay
     * @dev Permissionless - anyone can call once activation time is reached
     */
    function activate() external onlyPending {
        if (block.timestamp < activationTime) revert TooEarlyToActivate();

        CurveState oldState = state;
        state = CurveState.ACTIVE;

        emit StateChanged(appId, oldState, CurveState.ACTIVE);
        emit CurveActivated(appId, activationTime, deadline);
    }

    /**
     * @notice Force graduation after deadline is reached
     * @dev Permissionless - anyone can call once deadline is passed
     *      Graduates with whatever ELTA has been raised, even if below target
     */
    function forceGraduate() external nonReentrant {
        if (state == CurveState.GRADUATED) revert AlreadyGraduated();
        if (state == CurveState.CANCELLED) revert AlreadyCancelled();
        if (block.timestamp < deadline) revert DeadlineNotReached();

        // If still pending, activate first
        if (state == CurveState.PENDING) {
            state = CurveState.ACTIVE;
            emit StateChanged(appId, CurveState.PENDING, CurveState.ACTIVE);
        }

        emit ForceGraduated(appId, reserveElta);

        // Graduate with whatever has been raised
        _graduate();
    }

    /**
     * @notice Cancel the curve before activation
     * @dev Only creator can cancel, only while PENDING
     *      Refunds seed ELTA and tokens to creator
     */
    function cancel() external nonReentrant onlyPending {
        if (msg.sender != creator) revert OnlyCreator();

        CurveState oldState = state;
        state = CurveState.CANCELLED;

        uint256 eltaToRefund = reserveElta;
        uint256 tokensToRefund = reserveToken;

        // Clear reserves
        reserveElta = 0;
        reserveToken = 0;

        // Refund to creator
        if (eltaToRefund > 0) {
            ELTA.safeTransfer(creator, eltaToRefund);
        }
        if (tokensToRefund > 0) {
            IERC20(address(TOKEN)).safeTransfer(creator, tokensToRefund);
        }

        emit StateChanged(appId, oldState, CurveState.CANCELLED);
        emit CurveCancelled(appId, eltaToRefund, tokensToRefund);
    }

    /**
     * @notice Sweep accumulated fees to FeeCollector
     * @dev Permissionless - anyone can trigger fee forwarding
     */
    function sweepFees() external nonReentrant {
        if (feeCollector == address(0)) return;
        if (pendingFees == 0) return;

        uint256 amount = pendingFees;
        pendingFees = 0;

        ELTA.approve(feeCollector, amount);
        IFeeCollector(feeCollector).depositElta(appId, FeeKind.TRADING_FEE, amount);

        emit FeesSwepted(appId, amount, feeCollector);
    }

    /**
     * @notice Set the FeeCollector address
     * @param _feeCollector New FeeCollector address
     * @dev Callable by governance or factory
     */
    function setFeeCollector(address _feeCollector) external {
        if (msg.sender != governance && msg.sender != appFactory) revert OnlyGovernance();

        address oldCollector = feeCollector;
        feeCollector = _feeCollector;

        emit FeeCollectorUpdated(oldCollector, _feeCollector);
    }

    /**
     * @notice Get lifecycle state information
     * @return currentState Current curve state
     * @return activation When curve becomes/became active
     * @return deadlineTime When forced graduation can happen
     * @return canActivate Whether curve can be activated now
     * @return canForceGraduate Whether curve can be force graduated now
     */
    function getLifecycleInfo()
        external
        view
        returns (
            CurveState currentState,
            uint256 activation,
            uint256 deadlineTime,
            bool canActivate,
            bool canForceGraduate
        )
    {
        currentState = state;
        activation = activationTime;
        deadlineTime = deadline;
        canActivate = state == CurveState.PENDING && block.timestamp >= activationTime;
        canForceGraduate = state != CurveState.GRADUATED && state != CurveState.CANCELLED && block.timestamp >= deadline;
    }
}
