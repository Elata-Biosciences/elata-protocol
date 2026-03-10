// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeKind} from "./FeeKind.sol";
import {IAppRegistry} from "../interfaces/IAppRegistry.sol";
import {IContributorSplit} from "../interfaces/IContributorSplit.sol";
import {Errors} from "../utils/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FeeSwapper
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Unified v2 fee pipeline:
 * - `accrue(...)` is the final routing surface (all user-facing fees route 80/20 to contributors/treasury)
 * - optional DEX swap helpers to convert fee assets to ELTA prior to routing.
 */
contract FeeSwapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error OnlyAdmin();
    error OnlyGovernance();
    error RouterNotAllowed();
    error SwapFailed();
    error BelowMinSwapThreshold();

    // =========== Events (routing) ===========
    event FeeAccrued(uint256 indexed appId, FeeKind indexed kind, address indexed asset, uint256 amount, address payer);
    event FeeRoutedToTreasury(uint256 indexed appId, FeeKind indexed kind, address indexed asset, uint256 amount);
    event FeeRoutedToContributors(
        uint256 indexed appId,
        FeeKind indexed kind,
        address indexed asset,
        uint256 contributorsAmount,
        address contributorSplit
    );
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event AppRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event AppTreasuryTakeUpdated(uint256 indexed appId, uint16 oldBps, uint16 newBps);
    event DefaultTreasuryTakeUpdated(uint16 oldBps, uint16 newBps);

    // =========== Events (swap helpers) ===========
    event Swapped(
        uint256 indexed appId,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address caller
    );
    event RouterAllowlistUpdated(address indexed router, bool allowed);
    event MinSwapThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // =========== State ===========
    IERC20 public immutable ELTA;
    address public admin;
    address public governance;
    address public treasury;
    IAppRegistry public appRegistry;

    // App revenue: treasury take in bps (0 => use defaultTreasuryTakeBps)
    uint16 public defaultTreasuryTakeBps = 2000; // 20%
    mapping(uint256 => uint16) public appTreasuryTakeBps;

    // Swap helper configuration
    uint256 public minSwapThreshold = 1 ether;
    mapping(address => bool) public isRouterAllowed;
    address[] internal _allowedRouters;

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    constructor(address _elta, address _admin, address _governance, address _treasury, address _appRegistry) {
        if (_elta == address(0) || _admin == address(0) || _governance == address(0) || _treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_appRegistry == address(0)) revert Errors.ZeroAddress();

        ELTA = IERC20(_elta);
        admin = _admin;
        governance = _governance;
        treasury = _treasury;
        appRegistry = IAppRegistry(_appRegistry);
    }

    /**
     * @notice Route fees for an appId with an explicit FeeKind.
     * @dev Caller transfers `asset` into this contract via transferFrom.
     */
    function accrue(uint256 appId, FeeKind kind, address asset, uint256 amount, address payer) external nonReentrant {
        if (asset == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit FeeAccrued(appId, kind, asset, amount, payer);

        _routeFromBalance(appId, kind, asset, amount, payer);
    }

    function _routeFromBalance(uint256 appId, FeeKind kind, address asset, uint256 amount, address payer) internal {
        // If app is paused, treat all incoming fees as protocol-controlled and route to treasury.
        IAppRegistry.AppInfo memory info = appRegistry.getApp(appId);
        if (info.paused) {
            IERC20(asset).safeTransfer(treasury, amount);
            emit FeeRoutedToTreasury(appId, kind, asset, amount);
            return;
        }

        // Protocol-owned FeeKinds always route 100% to treasury.
        if (_isProtocolKind(kind)) {
            IERC20(asset).safeTransfer(treasury, amount);
            emit FeeRoutedToTreasury(appId, kind, asset, amount);
            return;
        }

        // All remaining FeeKinds are app revenue (80/20).
        // If a new FeeKind is added and not classified, fail closed.
        if (!_isAppRevenueKind(kind)) revert Errors.InvalidAmount();

        uint16 takeBps = appTreasuryTakeBps[appId];
        if (takeBps == 0) takeBps = defaultTreasuryTakeBps;
        if (takeBps > 10_000) revert Errors.InvalidAmount();

        uint256 treasuryAmount = (amount * uint256(takeBps)) / 10_000;
        uint256 contributorsAmount = amount - treasuryAmount;

        if (treasuryAmount > 0) {
            IERC20(asset).safeTransfer(treasury, treasuryAmount);
            emit FeeRoutedToTreasury(appId, kind, asset, treasuryAmount);
        }

        address split = info.contributorSplit;
        if (split == address(0)) revert Errors.ZeroAddress();

        if (contributorsAmount > 0) {
            IERC20(asset).safeTransfer(split, contributorsAmount);
            IContributorSplit(split).onFeeReceived(kind, asset, contributorsAmount, payer);
            emit FeeRoutedToContributors(appId, kind, asset, contributorsAmount, split);
        }
    }

    // =========== Swap Helpers ===========

    function swap(
        uint256 appId,
        FeeKind kind,
        address tokenIn,
        uint256 amountIn,
        uint256 minOut,
        address router,
        address[] calldata path
    ) external nonReentrant returns (uint256 amountOut) {
        if (!isRouterAllowed[router]) revert RouterNotAllowed();
        if (amountIn == 0) revert Errors.InvalidAmount();
        if (path.length < 2) revert Errors.InvalidAmount();
        if (path[path.length - 1] != address(ELTA)) revert Errors.InvalidAmount();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = _executeSwap(tokenIn, amountIn, minOut, router, path);

        emit Swapped(appId, tokenIn, amountIn, address(ELTA), amountOut, msg.sender);
        _routeFromBalance(appId, kind, address(ELTA), amountOut, msg.sender);
    }

    function swapFromBalance(
        uint256 appId,
        FeeKind kind,
        address tokenIn,
        uint256 amountIn,
        uint256 minOut,
        address router,
        address[] calldata path
    ) external nonReentrant returns (uint256 amountOut) {
        if (!isRouterAllowed[router]) revert RouterNotAllowed();
        if (amountIn == 0) revert Errors.InvalidAmount();
        if (amountIn < minSwapThreshold) revert BelowMinSwapThreshold();
        if (path.length < 2) revert Errors.InvalidAmount();
        if (path[path.length - 1] != address(ELTA)) revert Errors.InvalidAmount();

        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        if (balance < amountIn) revert Errors.InvalidAmount();

        amountOut = _executeSwap(tokenIn, amountIn, minOut, router, path);

        // amountOut is ELTA held by this contract; route directly from balance.
        emit Swapped(appId, tokenIn, amountIn, address(ELTA), amountOut, msg.sender);
        _routeFromBalance(appId, kind, address(ELTA), amountOut, msg.sender);
    }

    function _executeSwap(address tokenIn, uint256 amountIn, uint256 minOut, address router, address[] calldata path)
        internal
        returns (uint256 amountOut)
    {
        uint256 eltaBefore = ELTA.balanceOf(address(this));
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);

        (bool success,) = router.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                amountIn,
                minOut,
                path,
                address(this),
                block.timestamp
            )
        );
        if (!success) revert SwapFailed();

        amountOut = ELTA.balanceOf(address(this)) - eltaBefore;
        if (amountOut < minOut) revert SwapFailed();
    }

    // =========== Admin/Gov Management ===========

    function setRouterAllowed(address router, bool allowed) external onlyGovernance {
        if (router == address(0)) revert Errors.ZeroAddress();

        if (allowed && !isRouterAllowed[router]) {
            _allowedRouters.push(router);
        } else if (!allowed && isRouterAllowed[router]) {
            _removeFromArray(router);
        }

        isRouterAllowed[router] = allowed;
        emit RouterAllowlistUpdated(router, allowed);
    }

    function getAllowedRouters() external view returns (address[] memory) {
        return _allowedRouters;
    }

    function _removeFromArray(address router) internal {
        uint256 len = _allowedRouters.length;
        for (uint256 i; i < len; ++i) {
            if (_allowedRouters[i] == router) {
                _allowedRouters[i] = _allowedRouters[len - 1];
                _allowedRouters.pop();
                break;
            }
        }
    }

    function setMinSwapThreshold(uint256 newThreshold) external onlyGovernance {
        uint256 old = minSwapThreshold;
        minSwapThreshold = newThreshold;
        emit MinSwapThresholdUpdated(old, newThreshold);
    }

    function setAppRegistry(address newRegistry) external onlyAdmin {
        if (newRegistry == address(0)) revert Errors.ZeroAddress();
        address old = address(appRegistry);
        appRegistry = IAppRegistry(newRegistry);
        emit AppRegistryUpdated(old, newRegistry);
    }

    function setTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) revert Errors.ZeroAddress();
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    function transferGovernance(address newGovernance) external onlyGovernance {
        if (newGovernance == address(0)) revert Errors.ZeroAddress();
        address old = governance;
        governance = newGovernance;
        emit GovernanceTransferred(old, newGovernance);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert Errors.ZeroAddress();
        address old = admin;
        admin = newAdmin;
        emit AdminTransferred(old, newAdmin);
    }

    function setDefaultTreasuryTakeBps(uint16 newBps) external onlyGovernance {
        if (newBps > 10_000) revert Errors.InvalidAmount();
        uint16 old = defaultTreasuryTakeBps;
        defaultTreasuryTakeBps = newBps;
        emit DefaultTreasuryTakeUpdated(old, newBps);
    }

    function setAppTreasuryTakeBps(uint256 appId, uint16 newBps) external onlyGovernance {
        if (newBps > 10_000) revert Errors.InvalidAmount();
        uint16 old = appTreasuryTakeBps[appId];
        appTreasuryTakeBps[appId] = newBps;
        emit AppTreasuryTakeUpdated(appId, old, newBps);
    }

    // =========== FeeKind Classification ===========

    function _isProtocolKind(FeeKind kind) internal pure returns (bool) {
        return kind == FeeKind.LAUNCH_FEE;
    }

    function _isAppRevenueKind(FeeKind kind) internal pure returns (bool) {
        return kind == FeeKind.TRADING_FEE || kind == FeeKind.TRANSFER_TAX || kind == FeeKind.CONTENT_SALE
            || kind == FeeKind.TOURNAMENT_FEE || kind == FeeKind.OTHER;
    }
}
