// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeKind} from "./FeeKind.sol";
import {IFeeRouterV2} from "../interfaces/IFeeRouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FeeCollector
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Aggregates protocol fees with per-app accounting and permissionless sweep functions.
 * @dev Receives both ELTA and app token fees, tracking pending amounts by app ID. Anyone may call
 *      the sweep functions to forward accumulated fees: ELTA routes to FeeSwapper for final routing,
 *      while app tokens route through FeeSwapper for conversion and then to final routing.
 *      Sweeps are per-app (and per-kind) to avoid unbounded loops.
 */
contract FeeCollector is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidAmount();
    error OnlyAdmin();
    error NothingToSweep();

    // =========== Events ===========
    event EltaDeposited(uint256 indexed appId, FeeKind indexed kind, uint256 amount, address indexed from);
    event AppTokenDeposited(
        uint256 indexed appId, FeeKind indexed kind, address indexed token, uint256 amount, address from
    );
    event EltaSwept(uint256 indexed appId, FeeKind indexed kind, uint256 amount, address indexed to, address sweeper);
    event AppTokenSwept(
        uint256 indexed appId, FeeKind indexed kind, address indexed token, uint256 amount, address to, address sweeper
    );
    event FeeRouterUpdated(address indexed oldFeeRouter, address indexed newFeeRouter);
    // Backwards-compat alias for older tests/scripts that still call this "FeeManager".
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);
    event FeeSwapperUpdated(address indexed oldFeeSwapper, address indexed newFeeSwapper);

    // =========== State ===========
    IERC20 public immutable ELTA;
    address public admin;
    address public feeRouter;
    address public feeSwapper;

    /// @notice Pending ELTA fees per app per fee kind
    mapping(uint256 => mapping(FeeKind => uint256)) public pendingEltaFees;

    /// @notice Pending app token fees per app per fee kind per token
    mapping(uint256 => mapping(FeeKind => mapping(address => uint256))) public pendingAppTokenFees;

    // =========== Modifiers ===========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    // =========== Constructor ===========
    constructor(address _elta, address _admin, address _feeRouter, address _feeSwapper) {
        if (_elta == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        // feeRouter and feeSwapper can be zero initially if not deployed yet

        ELTA = IERC20(_elta);
        admin = _admin;
        feeRouter = _feeRouter;
        feeSwapper = _feeSwapper;
    }

    // =========== Deposit Functions ===========

    /**
     * @notice Deposit ELTA fees for an app
     * @dev Called by bonding curves, modules, etc.
     * @param appId The app ID to credit
     * @param kind Fee kind tag used for final routing
     * @param amount Amount of ELTA to deposit
     */
    function depositElta(uint256 appId, FeeKind kind, uint256 amount) external nonReentrant {
        _depositElta(appId, kind, amount);
    }

    function _depositElta(uint256 appId, FeeKind kind, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);
        pendingEltaFees[appId][kind] += amount;

        emit EltaDeposited(appId, kind, amount, msg.sender);
    }

    /**
     * @notice Legacy convenience overload (defaults to protocol trading fee bucket).
     */
    function depositElta(uint256 appId, uint256 amount) external nonReentrant {
        _depositElta(appId, FeeKind.TRADING_FEE, amount);
    }

    /**
     * @notice Deposit app token fees for an app
     * @dev Called by AppToken transfer tax logic
     * @param appId The app ID to credit
     * @param kind Fee kind tag used for final routing
     * @param token The app token address
     * @param amount Amount of app tokens to deposit
     */
    function depositAppToken(uint256 appId, FeeKind kind, address token, uint256 amount) external nonReentrant {
        _depositAppToken(appId, kind, token, amount);
    }

    function _depositAppToken(uint256 appId, FeeKind kind, address token, uint256 amount) internal {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        pendingAppTokenFees[appId][kind][token] += amount;

        emit AppTokenDeposited(appId, kind, token, amount, msg.sender);
    }

    /**
     * @notice Legacy convenience overload (defaults to protocol transfer tax bucket).
     */
    function depositAppToken(uint256 appId, address token, uint256 amount) external nonReentrant {
        _depositAppToken(appId, FeeKind.TRANSFER_TAX, token, amount);
    }

    // =========== Sweep Functions (Permissionless) ===========

    /**
     * @notice Sweep pending ELTA fees for an app to FeeManager
     * @dev Permissionless - anyone can call. Approves and calls FeeRouterV2.accrue()
     *      so FeeRouterV2 can apply FeeKind policy and route funds.
     * @param appId The app ID to sweep
     * @param kind Fee kind bucket to sweep
     */
    function sweepElta(uint256 appId, FeeKind kind) external nonReentrant {
        _sweepElta(appId, kind, msg.sender);
    }

    function _sweepElta(uint256 appId, FeeKind kind, address sweeper) internal {
        uint256 amount = pendingEltaFees[appId][kind];
        if (amount == 0) revert NothingToSweep();

        pendingEltaFees[appId][kind] = 0;

        // Approve FeeRouter to pull and route
        ELTA.approve(feeRouter, amount);
        IFeeRouterV2(feeRouter).accrue(appId, kind, address(ELTA), amount, sweeper);

        emit EltaSwept(appId, kind, amount, feeRouter, sweeper);
    }

    /**
     * @notice Legacy convenience overload (defaults to protocol trading fee bucket).
     */
    function sweepElta(uint256 appId) external nonReentrant {
        _sweepElta(appId, FeeKind.TRADING_FEE, msg.sender);
    }

    /**
     * @notice Sweep pending app token fees for an app to FeeSwapper
     * @dev Permissionless - anyone can call. App tokens need to be swapped to ELTA.
     * @param appId The app ID to sweep
     * @param kind Fee kind bucket to sweep
     * @param token The app token address to sweep
     */
    function sweepAppToken(uint256 appId, FeeKind kind, address token) external nonReentrant {
        _sweepAppToken(appId, kind, token, msg.sender);
    }

    function _sweepAppToken(uint256 appId, FeeKind kind, address token, address sweeper) internal {
        uint256 amount = pendingAppTokenFees[appId][kind][token];
        if (amount == 0) revert NothingToSweep();

        pendingAppTokenFees[appId][kind][token] = 0;
        // Route directly through FeeSwapper (feeRouter) so app-token fees aren't stranded.
        IERC20(token).safeIncreaseAllowance(feeRouter, amount);
        IFeeRouterV2(feeRouter).accrue(appId, kind, token, amount, sweeper);

        emit AppTokenSwept(appId, kind, token, amount, feeRouter, sweeper);
    }

    /**
     * @notice Legacy convenience overload (defaults to protocol transfer tax bucket).
     */
    function sweepAppToken(uint256 appId, address token) external nonReentrant {
        _sweepAppToken(appId, FeeKind.TRANSFER_TAX, token, msg.sender);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Update the FeeRouterV2 address
     * @param _feeRouter New FeeRouterV2 address
     */
    function setFeeRouter(address _feeRouter) external onlyAdmin {
        if (_feeRouter == address(0)) revert ZeroAddress();
        address oldFeeRouter = feeRouter;
        feeRouter = _feeRouter;
        emit FeeRouterUpdated(oldFeeRouter, _feeRouter);
    }

    /**
     * @notice Legacy alias kept for older scripts/tests.
     * @dev Routes to setFeeRouter.
     */
    function setFeeManager(address _feeManager) external onlyAdmin {
        address old = feeRouter;
        feeRouter = _feeManager;
        emit FeeManagerUpdated(old, _feeManager);
        emit FeeRouterUpdated(old, _feeManager);
    }

    /**
     * @notice Legacy alias for older callers.
     */
    function feeManager() external view returns (address) {
        return feeRouter;
    }

    /**
     * @notice Update the FeeSwapper address
     * @param _feeSwapper New FeeSwapper address
     */
    function setFeeSwapper(address _feeSwapper) external onlyAdmin {
        if (_feeSwapper == address(0)) revert ZeroAddress();
        address oldFeeSwapper = feeSwapper;
        feeSwapper = _feeSwapper;
        emit FeeSwapperUpdated(oldFeeSwapper, _feeSwapper);
    }

    /**
     * @notice Transfer admin role
     * @param _admin New admin address
     */
    function transferAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
    }
}
