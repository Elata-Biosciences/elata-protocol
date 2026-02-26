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
import {FeeKind} from "../fees/FeeKind.sol";
import {IAppRegistry} from "../interfaces/IAppRegistry.sol";
import {IContributorSplit} from "../interfaces/IContributorSplit.sol";
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
    function depositElta(uint256 appId, FeeKind kind, uint256 amount) external;
}

interface IContributorSplitFactory {
    function createSplit(
        uint256 appId,
        address ownerSafe,
        address feeSwapper,
        IContributorSplit.Contributor[] calldata initialContributors
    ) external returns (address split);
}

interface IProtocolConfig {
    function activationDelay() external view returns (uint256);
    function maxCurveDuration() external view returns (uint256);
}

/**
 * @title AppFactory
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Permissionless factory for launching app tokens with integrated vesting and ecosystem allocations.
 * @dev Deploys an AppToken, AppBondingCurve, AppStakingVault, AppVestingWallet, and AppEcosystemVault
 *      for each new app. Token supply is split 50/25/25: half to the bonding curve for public sale,
 *      a quarter to a cliff-then-linear vesting wallet for the team, and a quarter to an ecosystem
 *      vault for airdrops. The factory collects a creation fee and registers the app in an on-chain
 *      registry. An emergency pause mechanism halts new launches if needed.
 */
contract AppFactory is AccessControl, ReentrancyGuard, IAppFactory {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public immutable ELTA;
    IUniswapV2Router02 public immutable router;
    address public immutable treasury;
    IAppFeeRouter public immutable appFeeRouter;
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

    /// @notice AppRegistry for app ownership + split lookup
    address public appRegistry;

    /// @notice ContributorSplitFactory for per-app split clones
    address public contributorSplitFactory;

    /// @notice FeeSwapper (v2 router) used by ContributorSplit instances
    address public feeSwapper;

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

        // vNext lifecycle (token optional)
        bool tokenLaunched;
        address ownerSafe;
        address contributorSplit;
        string metadataURI;
    }

    // Vesting defaults
    uint64 public constant DEFAULT_VESTING_CLIFF = 90 days; // 3 months
    uint64 public constant DEFAULT_VESTING_DURATION = 730 days; // 2 years

    uint256 public appCount;
    mapping(uint256 => App) public apps;
    mapping(address => uint256) public tokenToAppId;

    /// @dev Internal struct to reduce stack depth during app creation
    struct DeploymentAddresses {
        address token;
        address vault;
        address curve;
        address vestingWallet;
        address ecosystemVault;
    }

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
    error OnlyOwnerSafe();
    error TokenAlreadyLaunched();

    /**
     * @notice Initialize factory
     * @param _elta ELTA token address
     * @param _router Uniswap V2 router address
     * @param _treasury Treasury address
     * @param _appFeeRouter Fee router for trading fees
     * @param _appRewardsDistributor Legacy (unused) app rewards distributor
     * @param _rewardsDistributor Legacy (unused) rewards distributor
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
        // Legacy constructor args kept for backwards compatibility with older tests/scripts.
        // No fee value is routed to these contracts in the current design.
        _appRewardsDistributor = _appRewardsDistributor;
        _rewardsDistributor = _rewardsDistributor;

        require(
            address(_elta) != address(0) && address(_router) != address(0) && _treasury != address(0)
                && address(_appFeeRouter) != address(0) && address(_elataPoints) != address(0)
                && _governance != address(0) && _admin != address(0),
            "Zero address"
        );

        ELTA = _elta;
        router = _router;
        treasury = _treasury;
        appFeeRouter = _appFeeRouter;
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
     * @notice Set AppRegistry address
     */
    function setAppRegistry(address _appRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        appRegistry = _appRegistry;
    }

    /**
     * @notice Set ContributorSplitFactory address
     */
    function setContributorSplitFactory(address _factory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        contributorSplitFactory = _factory;
    }

    /**
     * @notice Set FeeRouterV2 address used by ContributorSplits
     */
    function setFeeSwapper(address _feeSwapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeSwapper = _feeSwapper;
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
    /// @notice Input parameters for createApp to reduce stack depth
    struct CreateAppParams {
        string name;
        string symbol;
        uint256 supply;
        address[] operators;
    }

    function createApp(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata, // description - set via AppToken.updateMetadata() after creation
        string calldata, // imageURI - set via AppToken.updateMetadata() after creation
        string calldata, // website - set via AppToken.updateMetadata() after creation
        address[] calldata operators
    ) external nonReentrant returns (uint256 appId) {
        // Create params struct on the stack to reduce param count
        CreateAppParams memory p;
        p.name = name;
        p.symbol = symbol;
        p.supply = supply;
        p.operators = operators;
        return _createAppInternal(p);
    }

    function _createAppInternal(CreateAppParams memory p) internal returns (uint256 appId) {
        if (paused) revert Paused();
        uint256 tokenSupply = p.supply == 0 ? defaultSupply : p.supply;
        require(tokenSupply > 0, "Invalid supply");

        // Phase A: register app without token (ownerSafe defaults to msg.sender)
        (appId,) = _createAppWithoutTokenInternal(msg.sender, "", new IContributorSplit.Contributor[](0));

        // Phase B: legacy wrapper does an immediate token launch, so it must also
        // collect the seed ELTA used to initialize the bonding curve reserves.
        _collectSeedEltaOnly();

        // Phase B: launch token immediately (backwards-compatible wrapper)
        _launchTokenForAppInternal(appId, p.name, p.symbol, tokenSupply, p.operators);
    }

    /// @dev Collect creation fee (protocol fee) from caller
    function _collectCreationFeeOnly() internal {
        if (creationFee == 0) return;
        require(ELTA.transferFrom(msg.sender, address(this), creationFee), "Transfer failed");

        if (feeCollector != address(0)) {
            ELTA.approve(feeCollector, creationFee);
            IFeeCollector(feeCollector).depositElta(0, FeeKind.LAUNCH_FEE, creationFee);
        } else {
            require(ELTA.transfer(treasury, creationFee), "Transfer failed");
        }
    }

    /// @dev Collect seed ELTA used to initialize the bonding curve reserves
    function _collectSeedEltaOnly() internal {
        require(ELTA.transferFrom(msg.sender, address(this), seedElta), "Transfer failed");
    }

    /**
     * @notice Phase A: register an app without launching a token
     * @dev Caller pays the protocol creation fee. App ownership is attributed to ownerSafe.
     */
    function createAppWithoutToken(
        address ownerSafe,
        string calldata metadataURI,
        IContributorSplit.Contributor[] calldata initialContributors
    ) external nonReentrant returns (uint256 appId, address contributorSplit) {
        if (paused) revert Paused();
        return _createAppWithoutTokenInternal(ownerSafe, metadataURI, initialContributors);
    }

    function _createAppWithoutTokenInternal(
        address ownerSafe,
        string memory metadataURI,
        IContributorSplit.Contributor[] memory initialContributors
    ) internal returns (uint256 appId, address contributorSplit) {
        if (ownerSafe == address(0)) revert ZeroAddress();
        if (appRegistry == address(0) || contributorSplitFactory == address(0) || feeSwapper == address(0)) {
            revert InvalidParameters();
        }

        // Collect protocol creation fee (no seed ELTA yet)
        _collectCreationFeeOnly();

        appId = appCount++;

        // Deploy per-app ContributorSplit clone
        contributorSplit = IContributorSplitFactory(contributorSplitFactory)
            .createSplit(appId, ownerSafe, feeSwapper, initialContributors);

        // Register app in canonical registry
        IAppRegistry(appRegistry).registerApp(appId, ownerSafe, contributorSplit, metadataURI);

        // Populate local app record (token/curve/etc remain zero until Phase B)
        apps[appId] = App({
            creator: ownerSafe,
            token: address(0),
            vault: address(0),
            curve: address(0),
            vestingWallet: address(0),
            ecosystemVault: address(0),
            pair: address(0),
            locker: address(0),
            createdAt: uint64(block.timestamp),
            graduatedAt: 0,
            graduated: false,
            totalRaised: 0,
            finalSupply: 0,
            tokenLaunched: false,
            ownerSafe: ownerSafe,
            contributorSplit: contributorSplit,
            metadataURI: metadataURI
        });
    }

    /**
     * @notice Phase B: launch token for an already-registered appId
     * @dev Must be called by the app ownerSafe (Safe smart account).
     */
    function launchTokenForApp(
        uint256 appId,
        string calldata name,
        string calldata symbol,
        uint256 supply,
        address[] calldata operators
    ) external nonReentrant returns (address token, address curve) {
        App storage app = apps[appId];
        if (app.ownerSafe == address(0)) revert AppNotFound();
        if (msg.sender != app.ownerSafe) revert OnlyOwnerSafe();
        if (app.tokenLaunched) revert TokenAlreadyLaunched();

        uint256 tokenSupply = supply == 0 ? defaultSupply : supply;
        require(tokenSupply > 0, "Invalid supply");

        // Collect seed ELTA used for curve initialization
        _collectSeedEltaOnly();

        (token, curve) = _launchTokenForAppInternal(appId, name, symbol, tokenSupply, operators);
    }

    /// @dev Deploy all contracts for new app
    function _deployContracts(
        uint256 appId,
        address ownerSafe,
        string memory name,
        string memory symbol,
        uint256 tokenSupply
    ) internal returns (DeploymentAddresses memory addrs) {
        addrs.token = AppDeploymentLib.deployToken(
            AppToken.InitParams({
                name: name,
                symbol: symbol,
                decimals: defaultDecimals,
                maxSupply: tokenSupply,
                creator: ownerSafe,
                admin: address(this),
                governance: governance,
                appRewardsDistributor: address(0),
                rewardsDistributor: address(0),
                treasury: treasury
            })
        );
        addrs.vault = AppDeploymentLib.deployVault(name, symbol, addrs.token, address(this));

        // Read protocol config with fallbacks
        uint256 _activationDelay =
            protocolConfig != address(0) ? IProtocolConfig(protocolConfig).activationDelay() : 1 hours;
        uint256 _maxDuration =
            protocolConfig != address(0) ? IProtocolConfig(protocolConfig).maxCurveDuration() : 30 days;

        addrs.curve = AppDeploymentLib.deployCurve(
            AppBondingCurve.InitParams({
                appId: appId,
                factory: address(this),
                elta: ELTA,
                token: AppToken(addrs.token),
                router: router,
                targetRaisedElta: targetRaisedElta,
                lpLockDuration: lpLockDuration,
                lpBeneficiary: ownerSafe,
                treasury: treasury,
                appFeeRouter: appFeeRouter,
                elataPoints: elataPoints,
                governance: governance,
                activationDelay: _activationDelay,
                maxDuration: _maxDuration,
                creator: ownerSafe,
                feeCollector: feeCollector,
                referralRegistry: address(0)
            })
        );

        // Deploy vesting and ecosystem vaults
        addrs.vestingWallet = address(
            new AppVestingWallet(
                appId,
                addrs.token,
                ownerSafe,
                uint64(block.timestamp),
                DEFAULT_VESTING_CLIFF,
                DEFAULT_VESTING_DURATION,
                ownerSafe
            )
        );
        addrs.ecosystemVault = address(new AppEcosystemVault(appId, addrs.token, ownerSafe));
    }

    /// @dev Configure token, mint allocations, and set up roles
    function _configureApp(
        uint256 appId,
        address ownerSafe,
        DeploymentAddresses memory addrs,
        uint256 tokenSupply,
        address[] memory operators
    ) internal {
        uint256 curveShare = tokenSupply / 2;
        uint256 teamShare = tokenSupply / 4;
        uint256 ecosystemShare = tokenSupply - curveShare - teamShare;

        AppToken token = AppToken(addrs.token);

        // Configure token
        token.setVault(addrs.vault);
        token.setTransferFeeExempt(addrs.curve, true);
        token.setTransferFeeExempt(addrs.vestingWallet, true);
        token.setTransferFeeExempt(addrs.ecosystemVault, true);
        if (feeCollector != address(0)) {
            // Ensure LP-keyed transfer tax routes into the unified fee pipeline.
            token.setFeeCollector(feeCollector, appId);
        }

        // Mint tokens
        token.mint(addrs.curve, curveShare);
        token.mint(addrs.vestingWallet, teamShare);
        token.mint(addrs.ecosystemVault, ecosystemShare);
        token.revokeMinter(address(this));

        // Grant roles
        _grantOperatorRoles(token, operators);
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), ownerSafe);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), address(this));

        // Initialize curve and transfer ownership
        require(ELTA.transfer(addrs.curve, seedElta), "Transfer failed");
        AppBondingCurve(addrs.curve).initializeCurve(seedElta, curveShare);
        AppStakingVault(addrs.vault).transferOwnership(ownerSafe);
    }

    /// @dev Grant operator roles to addresses
    function _grantOperatorRoles(AppToken token, address[] memory operators) internal {
        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] != address(0)) {
                token.grantRole(token.APP_OPERATOR_ROLE(), operators[i]);
                token.grantRole(token.LP_MANAGER_ROLE(), operators[i]);
                token.grantRole(token.FEE_EXEMPT_MANAGER_ROLE(), operators[i]);
            }
        }
    }

    /// @dev Register app and emit event
    function _launchTokenForAppInternal(
        uint256 appId,
        string memory name,
        string memory symbol,
        uint256 tokenSupply,
        address[] memory operators
    ) internal returns (address token, address curve) {
        App storage app = apps[appId];
        address ownerSafe = app.ownerSafe;

        // Deploy and configure
        DeploymentAddresses memory addrs = _deployContracts(appId, ownerSafe, name, symbol, tokenSupply);
        _configureApp(appId, ownerSafe, addrs, tokenSupply, operators);

        // Persist to local record
        app.token = addrs.token;
        app.vault = addrs.vault;
        app.curve = addrs.curve;
        app.vestingWallet = addrs.vestingWallet;
        app.ecosystemVault = addrs.ecosystemVault;
        app.tokenLaunched = true;

        tokenToAppId[addrs.token] = appId;

        // Update canonical registry
        IAppRegistry(appRegistry).setTokenAndCurve(appId, addrs.token, addrs.curve);

        emit AppCreated(
            appId,
            ownerSafe,
            addrs.token,
            addrs.vault,
            addrs.curve,
            addrs.vestingWallet,
            addrs.ecosystemVault,
            tokenSupply / 2
        );

        if (feeManager != address(0)) {
            IFeeManager(feeManager).setAppCreator(appId, ownerSafe);
        }

        return (addrs.token, addrs.curve);
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
        if (!app.tokenLaunched || app.curve == address(0)) return (false, 0, 0);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 launchTime = curve.launchTimestamp();
        uint256 duration = curve.earlyBuyDuration();

        isInEarlyAccess = block.timestamp < launchTime + duration;
        earlyAccessEndsAt = launchTime + duration;
        xpRequired = curve.xpMinForEarlyBuy();
    }
}
