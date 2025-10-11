// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV2Router02 } from "../interfaces/IUniswapV2Router02.sol";
import { AppToken } from "./AppToken.sol";
import { AppBondingCurve, IAppFactory } from "./AppBondingCurve.sol";
import { AppDeploymentLib } from "./libraries/AppDeploymentLib.sol";

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
 *
 * NOTE: This contract is ~26KB (over EIP-170 24KB limit) but works fine on Anvil
 * for local development. Before mainnet deployment, optimize by:
 * - Removing complex view functions
 * - Using external library for deployment logic
 * - Or deploy to L2 where limits may be higher
 */
contract AppFactory is AccessControl, ReentrancyGuard, IAppFactory {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public immutable ELTA;
    IUniswapV2Router02 public immutable router;
    address public immutable treasury;

    // Launch parameters (immutable for size optimization)
    uint256 public constant seedElta = 100 ether;
    uint256 public constant targetRaisedElta = 42_000 ether;
    uint256 public constant defaultSupply = 1_000_000_000 ether;
    uint256 public constant lpLockDuration = 365 days * 2;
    uint8 public constant defaultDecimals = 18;
    uint256 public constant protocolFeeRate = 250;
    uint256 public constant creationFee = 10 ether;

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

    uint256 public appCount;
    mapping(uint256 => App) public apps;
    mapping(address => uint256) public tokenToAppId;

    // Events
    event AppCreated(
        uint256 indexed appId, address indexed creator, address indexed token, address curve
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

    constructor(IERC20 _elta, IUniswapV2Router02 _router, address _treasury, address _admin) {
        require(
            address(_elta) != address(0) && address(_router) != address(0)
                && _treasury != address(0) && _admin != address(0),
            "Zero address"
        );
        ELTA = _elta;
        router = _router;
        treasury = _treasury;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function setPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        paused = _paused;
    }

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

        // Collect fees
        require(
            ELTA.transferFrom(msg.sender, address(this), creationFee + seedElta), "Transfer failed"
        );
        if (creationFee > 0) {
            require(ELTA.transfer(treasury, creationFee), "Transfer failed");
        }

        // Deploy via library
        (address tokenAddr, address curveAddr) = AppDeploymentLib.deployTokenAndCurve(
            name,
            symbol,
            defaultDecimals,
            tokenSupply,
            msg.sender,
            address(this),
            appCount,
            ELTA,
            router,
            targetRaisedElta,
            lpLockDuration,
            treasury,
            protocolFeeRate,
            seedElta
        );

        // Register
        appId = appCount++;
        apps[appId] = App(
            msg.sender,
            tokenAddr,
            curveAddr,
            address(0),
            address(0),
            uint64(block.timestamp),
            0,
            false,
            0,
            0
        );
        tokenToAppId[tokenAddr] = appId;
        emit AppCreated(appId, msg.sender, tokenAddr, curveAddr);
    }

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

    function getApp(uint256 appId) external view returns (App memory) {
        return apps[appId];
    }
}
