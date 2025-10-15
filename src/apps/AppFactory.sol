// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV2Router02 } from "../interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../interfaces/IAppFeeRouter.sol";
import { IAppRewardsDistributor } from "../interfaces/IAppRewardsDistributor.sol";
import { IRewardsDistributor } from "../interfaces/IRewardsDistributor.sol";
import { IElataXP } from "../interfaces/IElataXP.sol";
import { AppToken } from "./AppToken.sol";
import { AppStakingVault } from "./AppStakingVault.sol";
import { AppBondingCurve, IAppFactory } from "./AppBondingCurve.sol";
import { AppDeploymentLib } from "./libraries/AppDeploymentLib.sol";

/**
 * @title AppFactory
 * @author Elata Biosciences
 * @notice Permissionless factory for launching app tokens with auto-staked creator shares
 * @dev Central registry and launch mechanism for the Elata app ecosystem
 *
 * Features:
 * - Permissionless app token creation
 * - Standardized bonding curve launches
 * - Auto-staked creator alignment (50% of supply)
 * - Snapshot-enabled vault for rewards
 * - Protocol fee collection via router
 * - Emergency pause mechanism
 *
 * Economics:
 * - Creators stake ELTA to launch apps
 * - Creator receives 50% of supply as staked position (not liquid)
 * - 50% goes to bonding curve for public sale
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
    IElataXP public immutable elataXP;
    address public immutable governance;

    // Launch parameters (immutable for size optimization)
    uint256 public constant seedElta = 100 ether;
    uint256 public constant targetRaisedElta = 42_000 ether;
    uint256 public constant defaultSupply = 1_000_000_000 ether;
    uint256 public constant lpLockDuration = 365 days * 2;
    uint8 public constant defaultDecimals = 18;
    uint256 public constant creationFee = 10 ether;

    bool public paused;

    struct App {
        address creator;
        address token;
        address vault; // NEW: staking vault
        address curve;
        address pair; // Set after graduation
        address locker; // Set after graduation
        uint64 createdAt;
        uint64 graduatedAt; // Set after graduation
        bool graduated;
        uint256 totalRaised; // Total ELTA raised
        uint256 finalSupply; // Final circulating supply
    }

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
        uint256 creatorStaked
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
     * @param _elataXP ElataXP token address
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
        IElataXP _elataXP,
        address _governance,
        address _admin
    ) {
        require(
            address(_elta) != address(0) && address(_router) != address(0)
                && _treasury != address(0) && address(_appFeeRouter) != address(0)
                && address(_appRewardsDistributor) != address(0)
                && address(_rewardsDistributor) != address(0) && address(_elataXP) != address(0)
                && _governance != address(0) && _admin != address(0),
            "Zero address"
        );

        ELTA = _elta;
        router = _router;
        treasury = _treasury;
        appFeeRouter = _appFeeRouter;
        appRewardsDistributor = _appRewardsDistributor;
        rewardsDistributor = _rewardsDistributor;
        elataXP = _elataXP;
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
     * @notice Create new app with auto-staked creator share
     * @param name App token name
     * @param symbol App token symbol
     * @param supply Total token supply (0 = use default)
     * @param description App description
     * @param imageURI App image URI
     * @param website App website
     * @return appId ID of created app
     */
    function createApp(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description,
        string calldata imageURI,
        string calldata website
    ) external nonReentrant returns (uint256 appId) {
        if (paused) revert Paused();
        uint256 tokenSupply = supply == 0 ? defaultSupply : supply;
        require(tokenSupply > 0, "Invalid supply");

        // Collect creation fees
        require(
            ELTA.transferFrom(msg.sender, address(this), creationFee + seedElta), "Transfer failed"
        );
        if (creationFee > 0) {
            require(ELTA.transfer(treasury, creationFee), "Transfer failed");
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
            elataXP,
            governance
        );

        // Configure token & curve
        uint256 creatorShare = tokenSupply / 2;
        uint256 curveShare = tokenSupply - creatorShare;

        AppToken token = AppToken(tokenAddr);

        // Set vault address on token (for fee exemptions)
        token.setVault(vaultAddr);

        // Mark bonding curve as exempt from transfer fees
        token.setTransferFeeExempt(curveAddr, true);

        token.mint(address(this), creatorShare);
        token.mint(curveAddr, curveShare);
        token.revokeMinter(address(this));
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), msg.sender);
        token.revokeRole(token.DEFAULT_ADMIN_ROLE(), address(this));

        require(ELTA.transfer(curveAddr, seedElta), "Transfer failed");
        AppBondingCurve(curveAddr).initializeCurve(seedElta, curveShare);

        // Auto-stake creator share (50% of supply)
        AppStakingVault vault = AppStakingVault(vaultAddr);

        // Approve vault to pull tokens from factory
        token.approve(vaultAddr, creatorShare);

        // Stake on behalf of creator (factory is still owner at this point)
        vault.stakeFor(msg.sender, creatorShare);

        // Transfer vault ownership to creator AFTER auto-staking
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
            pair: address(0),
            locker: address(0),
            createdAt: uint64(block.timestamp),
            graduatedAt: 0,
            graduated: false,
            totalRaised: 0,
            finalSupply: 0
        });

        tokenToAppId[tokenAddr] = appId;

        emit AppCreated(appId, msg.sender, tokenAddr, vaultAddr, curveAddr, creatorShare);

        // NOTE: Metadata must be set by creator in separate transaction
        // token.updateMetadata() requires msg.sender == appCreator
        // Creator can call AppToken(tokenAddr).updateMetadata(description, imageURI, website) after launch
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
