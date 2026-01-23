// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FeeCollector
 * @author Elata Biosciences
 * @notice Single sink for all protocol fee assets with per-app accounting
 * @dev Receives ELTA fees and app token fees, maintains per-app accounting,
 *      and exposes permissionless sweep functions
 *
 * Key Design Rules:
 * - Per-app accounting: pendingEltaFees[appId], pendingAppTokenFees[appId][token]
 * - Permissionless sweeps: anyone can call sweep functions
 * - No unbounded loops: sweeps are always per-app, never "all apps"
 * - ELTA goes to FeeManager directly
 * - App tokens go to FeeSwapper for conversion
 */
contract FeeCollector is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidAmount();
    error OnlyAdmin();
    error NothingToSweep();

    // =========== Events ===========
    event EltaDeposited(uint256 indexed appId, uint256 amount, address indexed from);
    event AppTokenDeposited(uint256 indexed appId, address indexed token, uint256 amount, address indexed from);
    event EltaSwept(uint256 indexed appId, uint256 amount, address indexed to);
    event AppTokenSwept(uint256 indexed appId, address indexed token, uint256 amount, address indexed to);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);
    event FeeSwapperUpdated(address indexed oldFeeSwapper, address indexed newFeeSwapper);

    // =========== State ===========
    IERC20 public immutable ELTA;
    address public admin;
    address public feeManager;
    address public feeSwapper;

    /// @notice Pending ELTA fees per app
    mapping(uint256 => uint256) public pendingEltaFees;

    /// @notice Pending app token fees per app per token
    mapping(uint256 => mapping(address => uint256)) public pendingAppTokenFees;

    // =========== Modifiers ===========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    // =========== Constructor ===========
    constructor(address _elta, address _admin, address _feeManager, address _feeSwapper) {
        if (_elta == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        // feeManager and feeSwapper can be zero initially if not deployed yet

        ELTA = IERC20(_elta);
        admin = _admin;
        feeManager = _feeManager;
        feeSwapper = _feeSwapper;
    }

    // =========== Deposit Functions ===========

    /**
     * @notice Deposit ELTA fees for an app
     * @dev Called by bonding curves, modules, etc.
     * @param appId The app ID to credit
     * @param amount Amount of ELTA to deposit
     */
    function depositElta(uint256 appId, uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();

        ELTA.safeTransferFrom(msg.sender, address(this), amount);
        pendingEltaFees[appId] += amount;

        emit EltaDeposited(appId, amount, msg.sender);
    }

    /**
     * @notice Deposit app token fees for an app
     * @dev Called by AppToken transfer tax logic
     * @param appId The app ID to credit
     * @param token The app token address
     * @param amount Amount of app tokens to deposit
     */
    function depositAppToken(uint256 appId, address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        pendingAppTokenFees[appId][token] += amount;

        emit AppTokenDeposited(appId, token, amount, msg.sender);
    }

    // =========== Sweep Functions (Permissionless) ===========

    /**
     * @notice Sweep pending ELTA fees for an app to FeeManager
     * @dev Permissionless - anyone can call
     * @param appId The app ID to sweep
     */
    function sweepElta(uint256 appId) external nonReentrant {
        uint256 amount = pendingEltaFees[appId];
        if (amount == 0) revert NothingToSweep();

        pendingEltaFees[appId] = 0;
        ELTA.safeTransfer(feeManager, amount);

        emit EltaSwept(appId, amount, feeManager);
    }

    /**
     * @notice Sweep pending app token fees for an app to FeeSwapper
     * @dev Permissionless - anyone can call. App tokens need to be swapped to ELTA.
     * @param appId The app ID to sweep
     * @param token The app token address to sweep
     */
    function sweepAppToken(uint256 appId, address token) external nonReentrant {
        uint256 amount = pendingAppTokenFees[appId][token];
        if (amount == 0) revert NothingToSweep();

        pendingAppTokenFees[appId][token] = 0;
        IERC20(token).safeTransfer(feeSwapper, amount);

        emit AppTokenSwept(appId, token, amount, feeSwapper);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Update the FeeManager address
     * @param _feeManager New FeeManager address
     */
    function setFeeManager(address _feeManager) external onlyAdmin {
        if (_feeManager == address(0)) revert ZeroAddress();
        address oldFeeManager = feeManager;
        feeManager = _feeManager;
        emit FeeManagerUpdated(oldFeeManager, _feeManager);
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
