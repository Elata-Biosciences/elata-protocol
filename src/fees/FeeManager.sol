// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITreasuryUSDCVault} from "../interfaces/ITreasuryUSDCVault.sol";

/// @notice Minimal Uniswap V2 Router interface for swaps
interface IUniswapV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/**
 * @title FeeManager
 * @author Elata Biosciences
 * @notice Handles daily epoch distribution of ELTA fees
 * @dev Holds ELTA and distributes to stakers, veELTA holders, creators, and treasury
 *
 * Key Features:
 * - Per-app accounting
 * - Daily epochs with configurable length
 * - Configurable fee splits
 * - Caller incentives in USDC
 */
contract FeeManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidAmount();
    error InvalidEpochLength();
    error InvalidFeeSplits();
    error OnlyAdmin();
    error OnlyGovernance();
    error OnlyDepositor();
    error EpochNotEnded();
    error NothingToDistribute();

    // =========== Events ===========
    event EltaDeposited(uint256 indexed appId, uint256 amount, address indexed from);
    event EpochClosed(uint256 indexed appId, uint256 indexed epochId, uint256 totalDistributed);
    event CallerIncentivePaid(address indexed caller, uint256 amount, uint256 indexed epochId);
    event FeeSplitsUpdated(
        uint256 appStakersBps, uint256 veEltaBps, uint256 creatorBps, uint256 treasuryBps, uint256 referralBps
    );
    event DepositorUpdated(address indexed depositor, bool allowed);
    event AppCreatorUpdated(uint256 indexed appId, address indexed creator);
    event TreasurySwapExecuted(uint256 eltaIn, uint256 usdcOut);
    event SwapRouterUpdated(address indexed oldRouter, address indexed newRouter);

    // =========== Constants ===========
    uint256 public constant MIN_EPOCH_LENGTH = 1 hours;
    uint256 public constant MAX_EPOCH_LENGTH = 7 days;
    uint256 public constant MAX_CALLER_INCENTIVE_USDC = 25e6; // 25 USDC
    uint256 public constant MIN_INCENTIVE_THRESHOLD_USDC = 100e6; // 100 USDC
    uint256 public constant CALLER_INCENTIVE_BPS = 10; // 0.10%

    // =========== State ===========
    IERC20 public immutable ELTA;
    IERC20 public immutable USDC;
    address public admin;
    address public governance;
    address public appRewardsDistributor;
    address public veRewardsDistributor;
    address public treasuryVault;

    /// @notice Uniswap V2 router for ELTA→USDC swaps
    address public swapRouter;

    /// @notice Whether to swap treasury portion to USDC (default: true)
    bool public swapTreasuryToUsdc = true;

    uint256 public epochLength;
    uint256 public deploymentTime;

    /// @notice Pending ELTA to distribute per app
    mapping(uint256 => uint256) public pendingEltaToDistribute;

    /// @notice Last epoch close timestamp per app
    mapping(uint256 => uint256) public lastEpochClose;

    /// @notice Authorized depositors (FeeSwapper, FeeCollector)
    mapping(address => bool) public isDepositor;

    /// @notice Authorized AppFactory contracts that can register creators
    mapping(address => bool) public isAppFactory;

    /// @notice App creator addresses for creator fee share
    mapping(uint256 => address) public appCreator;

    /// @notice Fee splits in basis points (must sum to 10000)
    struct FeeSplitConfig {
        uint256 appStakersBps;
        uint256 veEltaBps;
        uint256 creatorBps;
        uint256 treasuryBps;
        uint256 referralBps;
    }

    FeeSplitConfig public feeSplitConfig;

    /// @notice ReferralRegistry for distributing referral rewards
    address public referralRegistry;

    // =========== Modifiers ===========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    modifier onlyDepositor() {
        if (!isDepositor[msg.sender]) revert OnlyDepositor();
        _;
    }

    // =========== Constructor ===========
    constructor(
        address _elta,
        address _usdc,
        address _admin,
        address _governance,
        address _appRewardsDistributor,
        address _veRewardsDistributor,
        address _treasuryVault,
        uint256 _epochLength
    ) {
        if (_elta == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        if (_governance == address(0)) revert ZeroAddress();
        if (_epochLength < MIN_EPOCH_LENGTH || _epochLength > MAX_EPOCH_LENGTH) {
            revert InvalidEpochLength();
        }

        ELTA = IERC20(_elta);
        USDC = IERC20(_usdc);
        admin = _admin;
        governance = _governance;
        appRewardsDistributor = _appRewardsDistributor;
        veRewardsDistributor = _veRewardsDistributor;
        treasuryVault = _treasuryVault;
        epochLength = _epochLength;
        deploymentTime = block.timestamp;

        // Default fee splits: 45% app stakers, 30% veELTA, 10% creator, 10% treasury, 5% referral
        feeSplitConfig = FeeSplitConfig({
            appStakersBps: 4500, veEltaBps: 3000, creatorBps: 1000, treasuryBps: 1000, referralBps: 500
        });
    }

    // =========== Deposit Function ===========

    /**
     * @notice Deposit ELTA fees for an app
     * @dev Called by FeeSwapper or FeeCollector
     * @param appId The app ID to credit
     * @param amount Amount of ELTA to deposit
     */
    function depositEltaForApp(uint256 appId, uint256 amount) external onlyDepositor nonReentrant {
        if (amount == 0) revert InvalidAmount();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);
        pendingEltaToDistribute[appId] += amount;

        emit EltaDeposited(appId, amount, msg.sender);
    }

    // =========== Epoch Close Function ===========

    /**
     * @notice Close the epoch for an app and distribute fees
     * @dev Permissionless - anyone can call to earn incentive
     * @param appId The app ID to close epoch for
     */
    function closeEpoch(uint256 appId) external nonReentrant {
        // Check epoch timing
        uint256 lastClose = lastEpochClose[appId];
        if (lastClose == 0) {
            lastClose = deploymentTime;
        }

        if (block.timestamp < lastClose + epochLength) {
            revert EpochNotEnded();
        }

        uint256 amountToDistribute = pendingEltaToDistribute[appId];

        // Update state first
        lastEpochClose[appId] = block.timestamp;
        pendingEltaToDistribute[appId] = 0;

        if (amountToDistribute == 0) {
            return; // Nothing to distribute, but epoch is closed
        }

        // Calculate splits
        uint256 appShare = (amountToDistribute * feeSplitConfig.appStakersBps) / 10000;
        uint256 veShare = (amountToDistribute * feeSplitConfig.veEltaBps) / 10000;
        uint256 creatorShare = (amountToDistribute * feeSplitConfig.creatorBps) / 10000;
        uint256 referralShare = (amountToDistribute * feeSplitConfig.referralBps) / 10000;
        uint256 treasuryShare = amountToDistribute - appShare - veShare - creatorShare - referralShare;

        // Distribute to app stakers
        if (appShare > 0 && appRewardsDistributor != address(0)) {
            ELTA.safeTransfer(appRewardsDistributor, appShare);
        }

        // Distribute to veELTA holders
        if (veShare > 0 && veRewardsDistributor != address(0)) {
            ELTA.safeTransfer(veRewardsDistributor, veShare);
        }

        // Distribute to creator
        address creator = appCreator[appId];
        if (creatorShare > 0 && creator != address(0)) {
            ELTA.safeTransfer(creator, creatorShare);
        } else if (creatorShare > 0) {
            // If no creator set, add to treasury
            treasuryShare += creatorShare;
        }

        // Distribute to referral pool
        // Note: ReferralRegistry tracks individual rewards via accrueReferralReward() on buy()
        if (referralShare > 0 && referralRegistry != address(0)) {
            ELTA.safeTransfer(referralRegistry, referralShare);
        } else if (referralShare > 0) {
            // If no referral registry, add to treasury
            treasuryShare += referralShare;
        }

        // Treasury share - swap to USDC and send to treasury vault
        if (treasuryShare > 0 && treasuryVault != address(0)) {
            if (swapTreasuryToUsdc && swapRouter != address(0)) {
                // Swap ELTA to USDC for treasury
                uint256 usdcOut = _swapEltaToUsdc(treasuryShare);
                if (usdcOut > 0) {
                    // Deposit via TreasuryVault to properly track revenue
                    USDC.approve(treasuryVault, usdcOut);
                    ITreasuryUSDCVault(treasuryVault).deposit(appId, usdcOut, getCurrentEpochId());
                    emit TreasurySwapExecuted(treasuryShare, usdcOut);
                } else {
                    // Swap failed - fallback to sending ELTA directly to avoid loss
                    ELTA.safeTransfer(treasuryVault, treasuryShare);
                }
            } else {
                // Fallback: send ELTA directly
                ELTA.safeTransfer(treasuryVault, treasuryShare);
            }
        }

        // Pay caller incentive
        _payCallerIncentive(msg.sender);

        uint256 epochId = getCurrentEpochId();
        emit EpochClosed(appId, epochId, amountToDistribute);
    }

    /**
     * @dev Swap ELTA to USDC via router
     * @param eltaAmount Amount of ELTA to swap
     * @return usdcOut Amount of USDC received
     */
    function _swapEltaToUsdc(uint256 eltaAmount) internal returns (uint256 usdcOut) {
        if (swapRouter == address(0) || eltaAmount == 0) return 0;

        uint256 usdcBefore = USDC.balanceOf(address(this));

        // Approve router
        ELTA.approve(swapRouter, eltaAmount);

        // Build path: ELTA -> USDC
        address[] memory path = new address[](2);
        path[0] = address(ELTA);
        path[1] = address(USDC);

        // Call router with fee-on-transfer support
        // swapExactTokensForTokensSupportingFeeOnTransferTokens accepts any slippage (minOut = 0)
        // In production, consider oracle-based minOut calculation
        try IUniswapV2Router(swapRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                eltaAmount,
                0, // Accept any output (could add oracle-based min)
                path,
                address(this),
                block.timestamp
            ) {
            usdcOut = USDC.balanceOf(address(this)) - usdcBefore;
        } catch {
            // Swap failed, return 0 and let caller handle fallback
            usdcOut = 0;
        }
    }

    /**
     * @dev Pay USDC incentive to caller
     */
    function _payCallerIncentive(address caller) internal {
        uint256 usdcBalance = USDC.balanceOf(address(this));

        if (usdcBalance >= MIN_INCENTIVE_THRESHOLD_USDC) {
            uint256 incentive = (usdcBalance * CALLER_INCENTIVE_BPS) / 10000;
            if (incentive > MAX_CALLER_INCENTIVE_USDC) {
                incentive = MAX_CALLER_INCENTIVE_USDC;
            }

            if (incentive > 0 && incentive <= usdcBalance) {
                USDC.safeTransfer(caller, incentive);
                emit CallerIncentivePaid(caller, incentive, getCurrentEpochId());
            }
        }
    }

    // =========== View Functions ===========

    /**
     * @notice Get current epoch ID (time-based)
     */
    function getCurrentEpochId() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / epochLength;
    }

    /**
     * @notice Check if epoch can be closed for an app
     * @param appId App ID to check
     * @return canClose True if epoch can be closed
     */
    function canCloseEpoch(uint256 appId) external view returns (bool canClose) {
        uint256 lastClose = lastEpochClose[appId];
        if (lastClose == 0) {
            lastClose = deploymentTime;
        }
        return block.timestamp >= lastClose + epochLength;
    }

    /**
     * @notice Get fee splits configuration
     */
    function feeSplits() external view returns (uint256, uint256, uint256, uint256, uint256) {
        return (
            feeSplitConfig.appStakersBps,
            feeSplitConfig.veEltaBps,
            feeSplitConfig.creatorBps,
            feeSplitConfig.treasuryBps,
            feeSplitConfig.referralBps
        );
    }

    // =========== Admin Functions ===========

    /**
     * @notice Set depositor status
     * @param depositor Address to set
     * @param allowed Whether to allow deposits
     */
    function setDepositor(address depositor, bool allowed) external onlyAdmin {
        if (depositor == address(0)) revert ZeroAddress();
        isDepositor[depositor] = allowed;
        emit DepositorUpdated(depositor, allowed);
    }

    /**
     * @notice Set app creator address for fee sharing
     * @param appId App ID
     * @param creator Creator address
     */
    /**
     * @notice Set app creator for fee distribution
     * @dev Callable by admin or authorized AppFactory
     * @param appId The app ID
     * @param creator The creator address
     */
    function setAppCreator(uint256 appId, address creator) external {
        if (msg.sender != admin && !isAppFactory[msg.sender]) {
            revert OnlyAdmin();
        }
        appCreator[appId] = creator;
        emit AppCreatorUpdated(appId, creator);
    }

    /**
     * @notice Set AppFactory authorization
     * @param factory AppFactory address
     * @param authorized Whether to authorize
     */
    function setAppFactory(address factory, bool authorized) external onlyAdmin {
        if (factory == address(0)) revert ZeroAddress();
        isAppFactory[factory] = authorized;
    }

    /**
     * @notice Update fee splits
     * @param appStakers Basis points for app stakers
     * @param veElta Basis points for veELTA holders
     * @param creatorShare Basis points for creator
     * @param treasury Basis points for treasury
     */
    function setFeeSplits(uint256 appStakers, uint256 veElta, uint256 creatorShare, uint256 treasury, uint256 referral)
        external
        onlyGovernance
    {
        if (appStakers + veElta + creatorShare + treasury + referral != 10000) {
            revert InvalidFeeSplits();
        }

        feeSplitConfig.appStakersBps = appStakers;
        feeSplitConfig.veEltaBps = veElta;
        feeSplitConfig.creatorBps = creatorShare;
        feeSplitConfig.treasuryBps = treasury;
        feeSplitConfig.referralBps = referral;

        emit FeeSplitsUpdated(appStakers, veElta, creatorShare, treasury, referral);
    }

    /**
     * @notice Update epoch length
     * @param _epochLength New epoch length in seconds
     */
    function setEpochLength(uint256 _epochLength) external onlyGovernance {
        if (_epochLength < MIN_EPOCH_LENGTH || _epochLength > MAX_EPOCH_LENGTH) {
            revert InvalidEpochLength();
        }
        epochLength = _epochLength;
    }

    /**
     * @notice Transfer admin role
     */
    function transferAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
    }

    /**
     * @notice Set swap router for ELTA→USDC swaps
     * @param _router New router address
     */
    function setSwapRouter(address _router) external onlyAdmin {
        address oldRouter = swapRouter;
        swapRouter = _router;
        emit SwapRouterUpdated(oldRouter, _router);
    }

    /**
     * @notice Enable/disable treasury swap to USDC
     * @param enabled Whether to swap treasury share to USDC
     */
    function setSwapTreasuryToUsdc(bool enabled) external onlyGovernance {
        swapTreasuryToUsdc = enabled;
    }

    /**
     * @notice Set ReferralRegistry for referral reward distribution
     * @param _referralRegistry New referral registry address
     */
    function setReferralRegistry(address _referralRegistry) external onlyAdmin {
        referralRegistry = _referralRegistry;
    }
}
