// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV2Router02 } from "../interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "../interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "../interfaces/IUniswapV2Pair.sol";
import { AppToken } from "./AppToken.sol";
import { LpLocker } from "./LpLocker.sol";
import { IAppFeeRouter } from "../interfaces/IAppFeeRouter.sol";
import { IElataXP } from "../interfaces/IElataXP.sol";

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

/**
 * @title AppBondingCurve
 * @author Elata Biosciences
 * @notice Constant-product bonding curve for fair app token distribution
 * @dev Buy-only curve that graduates to Uniswap LP at target threshold
 *
 * Features:
 * - Constant product formula (x * y = k)
 * - Fair price discovery with no premine
 * - Automatic graduation to DEX liquidity
 * - LP token locking for security
 * - Slippage protection
 * - Refund mechanism for overages
 *
 * Economics:
 * - Creator stakes ELTA to seed initial liquidity
 * - Buyers purchase tokens with ELTA along curve
 * - Price increases with each purchase
 * - At target raised, auto-creates locked LP
 */
contract AppBondingCurve is ReentrancyGuard {
    using SafeERC20 for IERC20;

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
    IElataXP public immutable elataXP;
    uint256 public immutable launchTimestamp;
    uint256 public xpMinForEarlyBuy = 100e18; // governance-configurable (default 100 XP)
    uint256 public earlyBuyDuration = 6 hours; // governance-configurable (default 6 hours)
    address public governance;

    // Events
    event CurveInitialized(
        uint256 indexed appId, uint256 seedElta, uint256 tokenSupply, uint256 initialK
    );
    event XPGateUpdated(uint256 minXP, uint256 duration);
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

    error AlreadyGraduated();
    error NotGraduated();
    error InsufficientOutput();
    error ZeroInput();
    error NotInitialized();
    error OnlyFactory();
    error InvalidAmount();
    error InsufficientXP();
    error OnlyGovernance();

    modifier onlyFactory() {
        if (msg.sender != appFactory) revert OnlyFactory();
        _;
    }

    modifier notGraduated() {
        if (graduated) revert AlreadyGraduated();
        _;
    }

    /**
     * @notice Initialize bonding curve contract
     * @param _appId Unique app identifier
     * @param _factory Factory contract address
     * @param _elta ELTA token address
     * @param _token App token address
     * @param _router Uniswap V2 router address
     * @param _targetRaisedElta Target ELTA to raise before graduation
     * @param _lpLockDuration Duration to lock LP tokens
     * @param _lpBeneficiary Address to receive LP tokens after lock
     * @param _treasury Protocol treasury address
     * @param _appFeeRouter App fee router for revenue forwarding
     * @param _elataXP ElataXP token address for early access gating
     * @param _governance Governance address for XP gate configuration
     */
    constructor(
        uint256 _appId,
        address _factory,
        IERC20 _elta,
        AppToken _token,
        IUniswapV2Router02 _router,
        uint256 _targetRaisedElta,
        uint256 _lpLockDuration,
        address _lpBeneficiary,
        address _treasury,
        IAppFeeRouter _appFeeRouter,
        IElataXP _elataXP,
        address _governance
    ) {
        require(_factory != address(0), "Zero factory");
        require(address(_elta) != address(0), "Zero ELTA");
        require(address(_token) != address(0), "Zero token");
        require(address(_router) != address(0), "Zero router");
        require(_targetRaisedElta > 0, "Zero target");
        require(_lpBeneficiary != address(0), "Zero beneficiary");
        require(_treasury != address(0), "Zero treasury");
        require(address(_elataXP) != address(0), "Zero XP");
        require(_governance != address(0), "Zero governance");
        // appFeeRouter can be address(0) to disable fee forwarding

        appId = _appId;
        appFactory = _factory;
        ELTA = _elta;
        TOKEN = _token;
        router = _router;
        uniFactory = IUniswapV2Factory(_router.factory());
        targetRaisedElta = _targetRaisedElta;
        lpLockDuration = _lpLockDuration;
        lpBeneficiary = _lpBeneficiary;
        treasury = _treasury;
        appFeeRouter = _appFeeRouter;
        elataXP = _elataXP;
        governance = _governance;
        launchTimestamp = block.timestamp;
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
     * @return tokensOut Actual tokens received
     */
    function buy(uint256 eltaIn, uint256 minTokensOut)
        external
        nonReentrant
        notGraduated
        returns (uint256 tokensOut)
    {
        if (eltaIn == 0) revert ZeroInput();
        if (reserveElta == 0) revert NotInitialized();

        // XP gating for early launch window
        if (block.timestamp < launchTimestamp + earlyBuyDuration) {
            if (elataXP.balanceOf(msg.sender) < xpMinForEarlyBuy) {
                revert InsufficientXP();
            }
        }

        // Calculate maximum ELTA we can accept before hitting target
        uint256 remainingToTarget =
            targetRaisedElta > reserveElta ? targetRaisedElta - reserveElta : 0;
        uint256 actualEltaIn = eltaIn > remainingToTarget ? remainingToTarget : eltaIn;

        if (actualEltaIn == 0) revert InvalidAmount();

        // Calculate tokens out
        tokensOut = getTokensOut(actualEltaIn);
        if (tokensOut < minTokensOut) revert InsufficientOutput();

        // Calculate fee ON TOP of trade (buyer pays extra)
        uint256 tradingFee = 0;
        if (address(appFeeRouter) != address(0)) {
            tradingFee = (actualEltaIn * appFeeRouter.feeBps()) / 10_000;
        }

        // Pull ELTA from buyer: curve amount + trading fee
        ELTA.safeTransferFrom(msg.sender, address(this), actualEltaIn + tradingFee);

        // Forward trading fee to RewardsDistributor via router (70/15/15 split)
        // FIXED: Use address(this) as payer since we already pulled the fee
        if (tradingFee > 0) {
            ELTA.approve(address(appFeeRouter), tradingFee);
            appFeeRouter.takeAndForwardFee(address(this), tradingFee);
        }

        // Update reserves with ELTA (no more legacy protocol fee deduction)
        reserveElta += actualEltaIn;
        reserveToken -= tokensOut;

        // Transfer tokens to buyer
        TOKEN.transfer(msg.sender, tokensOut);

        // Calculate new price for event
        uint256 newPrice = reserveToken > 0 ? (reserveElta * 1e18) / reserveToken : 0;

        emit TokensPurchased(
            appId, msg.sender, actualEltaIn, tokensOut, reserveElta, reserveToken, newPrice
        );

        // Refund excess ELTA if any
        uint256 refund = eltaIn - actualEltaIn;
        if (refund > 0) {
            ELTA.safeTransfer(msg.sender, refund);
        }

        // Check for graduation
        if (reserveElta >= targetRaisedElta) {
            _graduate();
        }
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
        graduated = true;

        // Create or get existing pair
        address pairAddress = uniFactory.getPair(address(TOKEN), address(ELTA));
        if (pairAddress == address(0)) {
            pairAddress = uniFactory.createPair(address(TOKEN), address(ELTA));
        }
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
        IUniswapV2Pair(pair).transfer(address(lpLocker), liquidity);
        lpLocker.lockLp(liquidity);

        emit AppGraduated(
            appId, address(TOKEN), pair, locker, lpUnlockAt, reserveElta, reserveToken
        );

        // Notify factory
        IAppFactory(appFactory).onAppGraduated(
            appId, pair, locker, lpUnlockAt, reserveElta, reserveToken
        );

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
     * @notice Check if a user can buy tokens
     * @param user User address to check
     * @return canBuy Whether the user can buy
     */
    function canUserBuy(address user) external view returns (bool canBuy) {
        if (graduated) return false;
        if (block.timestamp >= launchTimestamp + earlyBuyDuration) return true;
        return elataXP.balanceOf(user) >= xpMinForEarlyBuy;
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
}
