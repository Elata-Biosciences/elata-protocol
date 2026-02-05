// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TreasuryUSDCVault
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Simple USDC custody contract with per-app and per-epoch revenue accounting.
 * @dev Receives USDC from fee distribution, emits events for off-chain revenue tracking, and allows
 *      the treasury multisig to withdraw. Intentionally minimal: no yield strategies or DeFi integrations.
 */
contract TreasuryUSDCVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidAmount();
    error OnlyAdmin();
    error OnlyFeeManager();
    error OnlyTreasury();
    error InsufficientBalance();

    // =========== Events ===========
    event TreasuryRevenue(uint256 indexed appId, uint256 usdcAmount, uint256 indexed epochId);
    event Withdrawal(address indexed to, uint256 amount, address indexed caller);
    event TreasuryMultisigUpdated(address indexed oldMultisig, address indexed newMultisig);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    // =========== State ===========
    IERC20 public immutable USDC;
    address public admin;
    address public treasuryMultisig;
    address public feeManager;

    /// @notice Total USDC revenue ever received
    uint256 public totalRevenue;

    /// @notice Revenue received per app
    mapping(uint256 => uint256) public revenueByApp;

    /// @notice Revenue received per epoch
    mapping(uint256 => uint256) public revenueByEpoch;

    // =========== Modifiers ===========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyFeeManager() {
        if (msg.sender != feeManager) revert OnlyFeeManager();
        _;
    }

    modifier onlyTreasury() {
        if (msg.sender != treasuryMultisig) revert OnlyTreasury();
        _;
    }

    // =========== Constructor ===========
    constructor(address _usdc, address _admin, address _treasuryMultisig, address _feeManager) {
        if (_usdc == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        if (_treasuryMultisig == address(0)) revert ZeroAddress();
        // feeManager can be zero initially if not deployed yet

        USDC = IERC20(_usdc);
        admin = _admin;
        treasuryMultisig = _treasuryMultisig;
        feeManager = _feeManager;
    }

    // =========== Deposit Function ===========

    /**
     * @notice Deposit USDC revenue from fee settlement
     * @dev Only callable by FeeManager during daily settlement
     * @param appId The app ID this revenue is attributed to
     * @param amount Amount of USDC to deposit
     * @param epochId The epoch this settlement is for
     */
    function deposit(uint256 appId, uint256 amount, uint256 epochId) external onlyFeeManager nonReentrant {
        if (amount == 0) revert InvalidAmount();

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        totalRevenue += amount;
        revenueByApp[appId] += amount;
        revenueByEpoch[epochId] += amount;

        emit TreasuryRevenue(appId, amount, epochId);
    }

    // =========== Withdrawal Function ===========

    /**
     * @notice Withdraw USDC to treasury multisig
     * @dev Only callable by treasury multisig
     * @param amount Amount of USDC to withdraw
     */
    function withdraw(uint256 amount) external onlyTreasury nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (amount > USDC.balanceOf(address(this))) revert InsufficientBalance();

        USDC.safeTransfer(treasuryMultisig, amount);

        emit Withdrawal(treasuryMultisig, amount, msg.sender);
    }

    // =========== View Functions ===========

    /**
     * @notice Get current USDC balance
     * @return Current USDC balance in vault
     */
    function balance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    // =========== Admin Functions ===========

    /**
     * @notice Update the treasury multisig address
     * @param _treasuryMultisig New treasury multisig address
     */
    function setTreasuryMultisig(address _treasuryMultisig) external onlyAdmin {
        if (_treasuryMultisig == address(0)) revert ZeroAddress();
        address oldMultisig = treasuryMultisig;
        treasuryMultisig = _treasuryMultisig;
        emit TreasuryMultisigUpdated(oldMultisig, _treasuryMultisig);
    }

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
     * @notice Transfer admin role
     * @param _admin New admin address
     */
    function transferAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
    }
}
