// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV2Router02 } from "../interfaces/IUniswapV2Router02.sol";
import { AppToken } from "./AppToken.sol";
import { AppBondingCurve, IAppFactory } from "./AppBondingCurve.sol";

/**
 * @title AppFactory
 * @author Elata Biosciences
 * @notice Permissionless factory for launching app tokens with bonding curves
 * @dev Central registry and launch mechanism for the Elata app ecosystem
 *
 * Features:
 * - Permissionless app token creation
 * - Standardized bonding curve launches
 * - Configurable launch parameters
 * - Comprehensive app registry
 * - Protocol fee collection
 * - Emergency pause mechanism
 *
 * Economics:
 * - Creators stake ELTA to launch apps
 * - Protocol collects fees for treasury
 * - Automated liquidity provision
 * - LP token locking for security
 */
contract AppFactory is AccessControl, ReentrancyGuard, IAppFactory {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant PARAMS_ROLE = keccak256("PARAMS_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Core protocol integration
    IERC20 public immutable ELTA;
    IUniswapV2Router02 public immutable router;
    address public immutable treasury;

    // Launch parameters (governable)
    uint256 public seedElta = 100 ether; // Creator stake to seed curve
    uint256 public targetRaisedElta = 42_000 ether; // Graduation threshold
    uint256 public defaultSupply = 1_000_000_000 ether; // Default token supply
    uint256 public lpLockDuration = 365 days * 2; // LP lock duration
    uint8 public defaultDecimals = 18; // Default token decimals
    uint256 public protocolFeeRate = 250; // 2.5% protocol fee
    uint256 public creationFee = 10 ether; // Fee to create app (in ELTA)

    bool public paused;

    struct App {
        address creator;
        address token;
        address curve;
        address pair; // Set after graduation
        address locker; // Set after graduation
        uint64 createdAt;
        uint64 graduatedAt; // Set after graduation
        bool graduated;
        uint256 totalRaised; // Total ELTA raised
        uint256 finalSupply; // Final circulating supply
    }

    // State
    uint256 public appCount;
    mapping(uint256 => App) public apps;
    mapping(address => uint256[]) public creatorApps; // creator => app IDs
    mapping(address => uint256) public tokenToAppId; // token => app ID

    // Events
    event AppCreated(
        uint256 indexed appId,
        address indexed creator,
        string name,
        string symbol,
        address token,
        address curve,
        uint256 seedElta,
        uint256 supply
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

    event ParametersUpdated(
        uint256 seedElta,
        uint256 targetRaised,
        uint256 defaultSupply,
        uint256 lpLockDuration,
        uint8 defaultDecimals,
        uint256 protocolFeeRate,
        uint256 creationFee
    );

    event CreationFeeCollected(uint256 indexed appId, address creator, uint256 amount);

    error Paused();
    error ZeroAddress();
    error InvalidParameters();
    error AppNotFound();

    /**
     * @notice Initialize app factory
     * @param _elta ELTA token address
     * @param _router Uniswap V2 router address
     * @param _treasury Treasury address for fees
     * @param _admin Admin address
     */
    constructor(IERC20 _elta, IUniswapV2Router02 _router, address _treasury, address _admin) {
        if (address(_elta) == address(0)) revert ZeroAddress();
        if (address(_router) == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        ELTA = _elta;
        router = _router;
        treasury = _treasury;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PARAMS_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @notice Update launch parameters (governance only)
     * @param _seedElta Creator stake amount
     * @param _targetRaised Target ELTA to raise
     * @param _defaultSupply Default token supply
     * @param _lpLockDuration LP lock duration
     * @param _defaultDecimals Default token decimals
     * @param _protocolFeeRate Protocol fee rate (basis points)
     * @param _creationFee Creation fee in ELTA
     */
    function setParameters(
        uint256 _seedElta,
        uint256 _targetRaised,
        uint256 _defaultSupply,
        uint256 _lpLockDuration,
        uint8 _defaultDecimals,
        uint256 _protocolFeeRate,
        uint256 _creationFee
    ) external onlyRole(PARAMS_ROLE) {
        if (_seedElta == 0) revert InvalidParameters();
        if (_targetRaised <= _seedElta) revert InvalidParameters();
        if (_defaultSupply == 0) revert InvalidParameters();
        if (_lpLockDuration < 30 days) revert InvalidParameters();
        if (_protocolFeeRate > 1000) revert InvalidParameters(); // Max 10%

        seedElta = _seedElta;
        targetRaisedElta = _targetRaised;
        defaultSupply = _defaultSupply;
        lpLockDuration = _lpLockDuration;
        defaultDecimals = _defaultDecimals;
        protocolFeeRate = _protocolFeeRate;
        creationFee = _creationFee;

        emit ParametersUpdated(
            _seedElta,
            _targetRaised,
            _defaultSupply,
            _lpLockDuration,
            _defaultDecimals,
            _protocolFeeRate,
            _creationFee
        );
    }

    /**
     * @notice Pause/unpause app creation
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        paused = _paused;
    }

    /**
     * @notice Create new app with token and bonding curve
     * @param name Token name
     * @param symbol Token symbol
     * @param supply Token supply (0 for default)
     * @param description App description
     * @param imageURI App image URI
     * @param website App website
     * @return appId New app ID
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

        // Use default supply if not specified
        uint256 tokenSupply = supply == 0 ? defaultSupply : supply;
        require(tokenSupply > 0, "Invalid supply");

        // Collect creation fee and seed ELTA
        uint256 totalCost = creationFee + seedElta;
        ELTA.safeTransferFrom(msg.sender, address(this), totalCost);

        // Send creation fee to treasury
        if (creationFee > 0) {
            ELTA.safeTransfer(treasury, creationFee);
            emit CreationFeeCollected(appCount, msg.sender, creationFee);
        }

        // Deploy app token
        AppToken token =
            new AppToken(name, symbol, defaultDecimals, tokenSupply, msg.sender, address(this));

        // Deploy bonding curve
        AppBondingCurve curve = new AppBondingCurve(
            appCount,
            address(this),
            ELTA,
            token,
            router,
            targetRaisedElta,
            lpLockDuration,
            treasury, // LP beneficiary
            treasury,
            protocolFeeRate
        );

        // Mint full supply to curve
        token.mint(address(curve), tokenSupply);
        token.revokeMinter(address(this));

        // Initialize curve with seed ELTA
        ELTA.safeTransfer(address(curve), seedElta);
        curve.initializeCurve(seedElta, tokenSupply);

        // Note: Creator can update metadata separately using token.updateMetadata()

        // Register app
        appId = appCount;
        apps[appId] = App({
            creator: msg.sender,
            token: address(token),
            curve: address(curve),
            pair: address(0),
            locker: address(0),
            createdAt: uint64(block.timestamp),
            graduatedAt: 0,
            graduated: false,
            totalRaised: 0,
            finalSupply: 0
        });

        creatorApps[msg.sender].push(appId);
        tokenToAppId[address(token)] = appId;
        appCount++;

        emit AppCreated(
            appId, msg.sender, name, symbol, address(token), address(curve), seedElta, tokenSupply
        );
    }

    /**
     * @notice Callback from bonding curve on graduation
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
        if (appId >= appCount) revert AppNotFound();

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

    // View functions

    /**
     * @notice Get app details
     * @param appId App ID
     * @return App struct
     */
    function getApp(uint256 appId) external view returns (App memory) {
        return apps[appId];
    }

    /**
     * @notice Get apps created by address
     * @param creator Creator address
     * @return Array of app IDs
     */
    function getCreatorApps(address creator) external view returns (uint256[] memory) {
        return creatorApps[creator];
    }

    /**
     * @notice Get app ID from token address
     * @param token Token address
     * @return App ID
     */
    function getAppIdFromToken(address token) external view returns (uint256) {
        return tokenToAppId[token];
    }

    /**
     * @notice Get all graduated apps
     * @return Array of graduated app IDs
     */
    function getGraduatedApps() external view returns (uint256[] memory) {
        uint256 graduatedCount = 0;

        // Count graduated apps
        for (uint256 i = 0; i < appCount; i++) {
            if (apps[i].graduated) graduatedCount++;
        }

        // Build array
        uint256[] memory graduated = new uint256[](graduatedCount);
        uint256 index = 0;

        for (uint256 i = 0; i < appCount; i++) {
            if (apps[i].graduated) {
                graduated[index] = i;
                index++;
            }
        }

        return graduated;
    }

    /**
     * @notice Get launch statistics
     * @return totalApps Total apps created
     * @return graduatedApps Total graduated apps
     * @return totalValueLocked Total ELTA locked in curves
     * @return totalFeesCollected Total creation fees collected
     */
    function getLaunchStats()
        external
        view
        returns (
            uint256 totalApps,
            uint256 graduatedApps,
            uint256 totalValueLocked,
            uint256 totalFeesCollected
        )
    {
        totalApps = appCount;

        for (uint256 i = 0; i < appCount; i++) {
            if (apps[i].graduated) {
                graduatedApps++;
                totalValueLocked += apps[i].totalRaised;
            }
        }

        totalFeesCollected = graduatedApps * creationFee; // Approximation
    }
}
