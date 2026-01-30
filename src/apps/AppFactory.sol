// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAppFeeRouter} from "../interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../interfaces/IAppRewardsDistributor.sol";
import {IElataPoints} from "../interfaces/IElataPoints.sol";
import {IRewardsDistributor} from "../interfaces/IRewardsDistributor.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";
import {AppBondingCurve, IAppFactory} from "./AppBondingCurve.sol";
import {AppStakingVault} from "./AppStakingVault.sol";
import {AppToken} from "./AppToken.sol";
import {AppDeploymentLib} from "./libraries/AppDeploymentLib.sol";
import {AppVestingWallet} from "../vesting/AppVestingWallet.sol";
import {AppEcosystemVault} from "../vesting/AppEcosystemVault.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFeeManager {
    function setAppCreator(uint256 appId, address creator) external;
}

interface IFeeCollector {
    function depositElta(uint256 appId, uint256 amount) external;
}

interface IProtocolConfig {
    function activationDelay() external view returns (uint256);
    function maxCurveDuration() external view returns (uint256);
}

/**
 * @title AppFactory
 * @author Elata Biosciences
 * @notice Permissionless factory for launching app tokens with vesting and ecosystem allocations
 * @dev Central registry and launch mechanism for the Elata app ecosystem
 *
 * Features:
 * - Permissionless app token creation
 * - Standardized bonding curve launches
 * - Team vesting wallet deployment
 * - Ecosystem vault for airdrops
 * - Protocol fee collection via router
 * - Emergency pause mechanism
 *
 * Economics (50/25/25 split):
 * - 50% goes to bonding curve for public sale
 * - 25% goes to team vesting wallet (cliff + linear vest)
 * - 25% goes to ecosystem vault (for airdrops/initiatives)
 * - Protocol collects trading fees (forwarded to rewards)
 * - Automated liquidity provision on graduation
 * - LP token locking for security
 */
contract AppFactory is AccessControl, ReentrancyGuard, IAppFactory {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public immutable ELTA;
    IUniswapV2Router02 public immutable router;
    address public immutable treasury;
    IAppFeeRouter public immutable appFeeRouter;
    IAppRewardsDistributor public immutable appRewardsDistributor;
    IRewardsDistributor public immutable rewardsDistributor;
    IElataPoints public immutable elataPoints;
    address public immutable governance;

    // Launch parameters (immutable for size optimization)
    uint256 public constant seedElta = 100 ether;
    uint256 public constant targetRaisedElta = 42_000 ether;
    uint256 public constant defaultSupply = 10_000_000 ether;
    uint256 public constant lpLockDuration = 365 days * 2;
    uint8 public constant defaultDecimals = 18;
    uint256 public constant creationFee = 10 ether;

    bool public paused;

    /// @notice FeeManager for creator registration
    address public feeManager;

    /// @notice FeeCollector for routing creation fees through fee pipeline
    address public feeCollector;

    /// @notice ProtocolConfig for reading protocol parameters
    address public protocolConfig;

    /// @notice ReferralRegistry for referral tracking
    address public referralRegistry;

    struct App {
        address creator;
        address token;
        address vault; // Staking vault (optional, for compatibility)
        address curve;
        address vestingWallet; // Team vesting wallet (25%)
        address ecosystemVault; // Ecosystem vault for airdrops (25%)
        address pair; // Set after graduation
        address locker; // Set after graduation
        uint64 createdAt;
        uint64 graduatedAt; // Set after graduation
        bool graduated;
        uint256 totalRaised; // Total ELTA raised
        uint256 finalSupply; // Final circulating supply
    }

    // Vesting defaults
    uint64 public constant DEFAULT_VESTING_CLIFF = 90 days; // 3 months
    uint64 public constant DEFAULT_VESTING_DURATION = 730 days; // 2 years

    uint256 public appCount;
    mapping(uint256 => App) public apps;
    mapping(address => uint256) public tokenToAppId;

    // Events
    event AppCreated(
        uint256 indexed appId,
        address indexed creator,
        address indexed token,
        address vault,
        address curve,
        address vestingWallet,
        address ecosystemVault,
        uint256 curveShare
    );

    event AppGraduated(
        uint256 indexed appId,
        address indexed token,
        address pair,
        address locker,
        uint256 unlockAt,
        uint256 totalRaised,
        uint256 finalSupply
    );

    error Paused();
    error ZeroAddress();
    error InvalidParameters();
    error AppNotFound();

    /**
     * @notice Initialize factory
     * @param _elta ELTA token address
     * @param _router Uniswap V2 router address
     * @param _treasury Treasury address
     * @param _appFeeRouter Fee router for trading fees
     * @param _appRewardsDistributor App rewards distributor
     * @param _rewardsDistributor Main rewards distributor
     * @param _elataPoints ElataPoints token address
     * @param _governance Governance address
     * @param _admin Admin address for roles
     */
    constructor(
        IERC20 _elta,
        IUniswapV2Router02 _router,
        address _treasury,
        IAppFeeRouter _appFeeRouter,
        IAppRewardsDistributor _appRewardsDistributor,
        IRewardsDistributor _rewardsDistributor,
        IElataPoints _elataPoints,
        address _governance,
        address _admin
    ) {
        require(
            address(_elta) != address(0) && address(_router) != address(0) && _treasury != address(0)
                && address(_appFeeRouter) != address(0) && address(_appRewardsDistributor) != address(0)
                && address(_rewardsDistributor) != address(0) && address(_elataPoints) != address(0)
                && _governance != address(0) && _admin != address(0),
            "Zero address"
        );

        ELTA = _elta;
        router = _router;
        treasury = _treasury;
        appFeeRouter = _appFeeRouter;
        appRewardsDistributor = _appRewardsDistributor;
        rewardsDistributor = _rewardsDistributor;
        elataPoints = _elataPoints;
        governance = _governance;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @notice Pause/unpause app creation
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        paused = _paused;
    }

    /**
     * @notice Set FeeManager for creator registration
     * @param _feeManager FeeManager address
     */
    function setFeeManager(address _feeManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeManager = _feeManager;
    }

    /**
     * @notice Set FeeCollector for routing creation fees through fee pipeline
     * @param _feeCollector FeeCollector address
     */
    function setFeeCollector(address _feeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeCollector = _feeCollector;
    }

    /**
     * @notice Set ProtocolConfig for reading protocol parameters
     * @param _protocolConfig ProtocolConfig address
     */
    function setProtocolConfig(address _protocolConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        protocolConfig = _protocolConfig;
    }

    /**
     * @notice Set ReferralRegistry for referral tracking
     * @param _referralRegistry ReferralRegistry address
     */
    function setReferralRegistry(address _referralRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        referralRegistry = _referralRegistry;
    }

    /**
     * @notice Create new app with auto-staked creator share
     * @param name App token name
     * @param symbol App token symbol
     * @param supply Total token supply (0 = use default)
     * @param operators Array of operator addresses to grant granular roles
     * @return appId ID of created app
     * @dev description, imageURI, website params are reserved for future use.
     *      Set via AppToken.updateMetadata() after creation.
     */
    function createApp(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata, // description - set via AppToken.updateMetadata() after creation
        string calldata, // imageURI - set via AppToken.updateMetadata() after creation
        string calldata, // website - set via AppToken.updateMetadata() after creation
        address[] calldata operators
    ) external nonReentrant returns (uint256 appId) {
        if (paused) revert Paused();
        uint256 tokenSupply = supply == 0 ? defaultSupply : supply;
        require(tokenSupply > 0, "Invalid supply");

        // Collect creation fees
        require(ELTA.transferFrom(msg.sender, address(this), creationFee + seedElta), "Transfer failed");

        // Route creation fee through fee pipeline (appId=0 for protocol-level fees)
        if (creationFee > 0) {
            if (feeCollector != address(0)) {
                ELTA.approve(feeCollector, creationFee);
                IFeeCollector(feeCollector).depositElta(0, creationFee);
            } else {
                // Fallback: direct to treasury
                require(ELTA.transfer(treasury, creationFee), "Transfer failed");
            }
        }

        // Deploy contracts via library (reduces AppFactory size)
        address tokenAddr = AppDeploymentLib.deployToken(
            name,
            symbol,
            defaultDecimals,
            tokenSupply,
            msg.sender,
            address(this),
            governance,
            address(appRewardsDistributor),
            address(rewardsDistributor),
            treasury
        );
        address vaultAddr = AppDeploymentLib.deployVault(name, symbol, tokenAddr, address(this));

        // Read activation delay and max duration from ProtocolConfig (with fallbacks)
        uint256 _activationDelay =
            protocolConfig != address(0) ? IProtocolConfig(protocolConfig).activationDelay() : 1 hours;
        uint256 _maxDuration =
            protocolConfig != address(0) ? IProtocolConfig(protocolConfig).maxCurveDuration() : 30 days;

        address curveAddr = AppDeploymentLib.deployCurve(
            appCount,
            address(this),
            ELTA,
            tokenAddr,
            router,
            targetRaisedElta,
            lpLockDuration,
            msg.sender,
            treasury,
            appFeeRouter,
            elataPoints,
            governance,
            _activationDelay,
            _maxDuration,
            feeCollector,
            referralRegistry
        );

        // Configure token & curve with 50/25/25 split
        uint256 curveShare = tokenSupply / 2; // 50% to bonding curve
        uint256 teamShare = tokenSupply / 4; // 25% to team vesting
        uint256 ecosystemShare = tokenSupply - curveShare - teamShare; // 25% to ecosystem

        AppToken token = AppToken(tokenAddr);

        // Set vault address on token (for fee exemptions)
        token.setVault(vaultAddr);

        // Mark bonding curve as exempt from transfer fees
        token.setTransferFeeExempt(curveAddr, true);

        // Deploy vesting wallet for team allocation
        AppVestingWallet vestingWallet = new AppVestingWallet(
            appCount,
            tokenAddr,
            msg.sender, // beneficiary = creator (team multisig)
            uint64(block.timestamp), // start = now
            DEFAULT_VESTING_CLIFF,
            DEFAULT_VESTING_DURATION,
            msg.sender // admin = creator
        );
        address vestingWalletAddr = address(vestingWallet);

        // Deploy ecosystem vault
        AppEcosystemVault ecosystemVault = new AppEcosystemVault(appCount, tokenAddr, msg.sender);
        address ecosystemVaultAddr = address(ecosystemVault);

        // Mark vesting and ecosystem vaults as exempt from transfer fees
        token.setTransferFeeExempt(vestingWalletAddr, true);
        token.setTransferFeeExempt(ecosystemVaultAddr, true);

        // Mint tokens according to 50/25/25 split
        token.mint(curveAddr, curveShare);
        token.mint(vestingWalletAddr, teamShare);
        token.mint(ecosystemVaultAddr, ecosystemShare);
        token.revokeMinter(address(this));

        // Grant granular roles to operators
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] != address(0)) {
                token.grantRole(token.APP_OPERATOR_ROLE(), operators[i]);
                token.grantRole(token.LP_MANAGER_ROLE(), operators[i]);
                token.grantRole(token.FEE_EXEMPT_MANAGER_ROLE(), operators[i]);
            }
        }

        // Transfer admin role to creator
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), msg.sender);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), address(this));

        require(ELTA.transfer(curveAddr, seedElta), "Transfer failed");
        AppBondingCurve(curveAddr).initializeCurve(seedElta, curveShare);

        // Transfer vault ownership to creator
        AppStakingVault vault = AppStakingVault(vaultAddr);
        vault.transferOwnership(msg.sender);

        // Register vault in rewards distributor with token mapping
        appRewardsDistributor.registerApp(vaultAddr, tokenAddr);

        // Register app
        appId = appCount++;
        apps[appId] = App({
            creator: msg.sender,
            token: tokenAddr,
            vault: vaultAddr,
            curve: curveAddr,
            vestingWallet: vestingWalletAddr,
            ecosystemVault: ecosystemVaultAddr,
            pair: address(0),
            locker: address(0),
            createdAt: uint64(block.timestamp),
            graduatedAt: 0,
            graduated: false,
            totalRaised: 0,
            finalSupply: 0
        });

        tokenToAppId[tokenAddr] = appId;

        emit AppCreated(
            appId, msg.sender, tokenAddr, vaultAddr, curveAddr, vestingWalletAddr, ecosystemVaultAddr, curveShare
        );

        // Register creator with FeeManager for fee share
        if (feeManager != address(0)) {
            IFeeManager(feeManager).setAppCreator(appId, msg.sender);
        }

        // NOTE: Metadata must be set by creator in separate transaction
        // token.updateMetadata() requires msg.sender == appCreator
        // Creator can call AppToken(tokenAddr).updateMetadata(description, imageURI, website) after
        // launch
    }

    /**
     * @notice Callback from bonding curve when app graduates
     * @param appId App ID
     * @param pair Uniswap pair address
     * @param locker LP locker address
     * @param unlockAt LP unlock timestamp
     * @param totalRaisedElta Total ELTA raised
     * @param finalSupply Final token supply
     */
    function onAppGraduated(
        uint256 appId,
        address pair,
        address locker,
        uint256 unlockAt,
        uint256 totalRaisedElta,
        uint256 finalSupply
    ) external override {
        require(appId < appCount, "Invalid app");
        App storage app = apps[appId];
        require(msg.sender == app.curve, "Only curve");

        app.pair = pair;
        app.locker = locker;
        app.graduatedAt = uint64(block.timestamp);
        app.graduated = true;
        app.totalRaised = totalRaisedElta;
        app.finalSupply = finalSupply;

        emit AppGraduated(appId, app.token, pair, locker, unlockAt, totalRaisedElta, finalSupply);
    }

    /**
     * @notice Get app details
     * @param appId App ID
     * @return App struct
     */
    function getApp(uint256 appId) external view returns (App memory) {
        return apps[appId];
    }

    /**
     * @notice Get app count
     * @return Total number of apps
     */
    function getAppCount() external view returns (uint256) {
        return appCount;
    }

    /**
     * @notice Get app ID by token address
     * @param token Token address
     * @return App ID
     */
    function getAppIdByToken(address token) external view returns (uint256) {
        return tokenToAppId[token];
    }

    /**
     * @notice Get app launch status and early access info
     * @param appId App ID
     * @return isInEarlyAccess Whether app is in early access period
     * @return earlyAccessEndsAt Timestamp when early access ends
     * @return xpRequired Minimum XP required for early access
     */
    function getAppLaunchStatus(uint256 appId)
        external
        view
        returns (bool isInEarlyAccess, uint256 earlyAccessEndsAt, uint256 xpRequired)
    {
        require(appId < appCount, "Invalid app");
        App storage app = apps[appId];
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 launchTime = curve.launchTimestamp();
        uint256 duration = curve.earlyBuyDuration();

        isInEarlyAccess = block.timestamp < launchTime + duration;
        earlyAccessEndsAt = launchTime + duration;
        xpRequired = curve.xpMinForEarlyBuy();
    }
}
