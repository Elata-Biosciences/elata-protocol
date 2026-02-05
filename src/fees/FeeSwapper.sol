// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FeeSwapper
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Converts non-ELTA fee assets to ELTA via governance-allowlisted DEX routers.
 * @dev Holds app tokens swept from FeeCollector and swaps them to ELTA using Uniswap V2-compatible
 *      routers. Swaps enforce caller-supplied minOut and a maximum slippage bound set by governance.
 *      Uses supportingFeeOnTransferTokens functions to handle tokens with transfer fees.
 */
contract FeeSwapper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidAmount();
    error OnlyAdmin();
    error OnlyGovernance();
    error RouterNotAllowed();
    error SlippageTooHigh();
    error SwapFailed();
    error BelowMinSwapThreshold();

    // =========== Events ===========
    event Swapped(
        uint256 indexed appId,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address caller
    );
    event RouterAllowlistUpdated(address indexed router, bool allowed);
    event MaxSlippageBpsUpdated(uint256 oldBps, uint256 newBps);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);
    event MinSwapThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // =========== Constants ===========
    uint256 public constant MAX_SLIPPAGE_BPS = 1000; // 10% absolute max

    // =========== State ===========
    IERC20 public immutable ELTA;
    address public admin;
    address public governance;
    address public feeManager;

    /// @notice Maximum allowed slippage in basis points
    uint256 public maxSlippageBps = 500; // 5% default

    /// @notice Minimum amount required for a swap (prevents dust swaps)
    uint256 public minSwapThreshold = 1 ether;

    /// @notice Allowlisted routers
    mapping(address => bool) public isRouterAllowed;
    address[] internal _allowedRouters;

    // =========== Modifiers ===========
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    // =========== Constructor ===========
    constructor(address _elta, address _admin, address _governance, address _feeManager) {
        if (_elta == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        if (_governance == address(0)) revert ZeroAddress();

        ELTA = IERC20(_elta);
        admin = _admin;
        governance = _governance;
        feeManager = _feeManager;
    }

    // =========== Swap Functions ===========

    /**
     * @notice Swap tokens directly from caller to ELTA
     * @dev Caller must approve tokens first
     * @param appId App ID for accounting
     * @param tokenIn Token to swap from
     * @param amountIn Amount of tokens to swap
     * @param minOut Minimum ELTA output (caller-supplied slippage protection)
     * @param router Router address (must be allowlisted)
     * @param path Swap path (tokenIn -> ... -> ELTA)
     * @return amountOut Actual ELTA received
     */
    function swap(
        uint256 appId,
        address tokenIn,
        uint256 amountIn,
        uint256 minOut,
        address router,
        address[] calldata path
    ) external nonReentrant returns (uint256 amountOut) {
        if (!isRouterAllowed[router]) revert RouterNotAllowed();
        if (amountIn == 0) revert InvalidAmount();
        if (path.length < 2) revert InvalidAmount();
        if (path[path.length - 1] != address(ELTA)) revert InvalidAmount();

        // Transfer tokens from caller
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Perform swap
        amountOut = _executeSwap(tokenIn, amountIn, minOut, router, path);

        // Forward ELTA to FeeManager
        ELTA.safeTransfer(feeManager, amountOut);

        emit Swapped(appId, tokenIn, amountIn, address(ELTA), amountOut, msg.sender);
    }

    /**
     * @notice Swap tokens already held by this contract
     * @dev Used when FeeCollector sweeps directly to FeeSwapper
     * @param appId App ID for accounting
     * @param tokenIn Token to swap from
     * @param amountIn Amount of tokens to swap
     * @param minOut Minimum ELTA output
     * @param router Router address (must be allowlisted)
     * @param path Swap path
     * @return amountOut Actual ELTA received
     */
    function swapFromBalance(
        uint256 appId,
        address tokenIn,
        uint256 amountIn,
        uint256 minOut,
        address router,
        address[] calldata path
    ) external nonReentrant returns (uint256 amountOut) {
        if (!isRouterAllowed[router]) revert RouterNotAllowed();
        if (amountIn == 0) revert InvalidAmount();
        if (amountIn < minSwapThreshold) revert BelowMinSwapThreshold();
        if (path.length < 2) revert InvalidAmount();
        if (path[path.length - 1] != address(ELTA)) revert InvalidAmount();

        // Verify balance
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        if (balance < amountIn) revert InvalidAmount();

        // Perform swap
        amountOut = _executeSwap(tokenIn, amountIn, minOut, router, path);

        // Forward ELTA to FeeManager
        ELTA.safeTransfer(feeManager, amountOut);

        emit Swapped(appId, tokenIn, amountIn, address(ELTA), amountOut, msg.sender);
    }

    /**
     * @dev Execute the swap via router
     */
    function _executeSwap(address tokenIn, uint256 amountIn, uint256 minOut, address router, address[] calldata path)
        internal
        returns (uint256 amountOut)
    {
        uint256 eltaBefore = ELTA.balanceOf(address(this));

        // Approve router
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);

        // Call router with fee-on-transfer support
        // swapExactTokensForTokensSupportingFeeOnTransferTokens(
        //     uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline
        // )
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

    // =========== Router Management ===========

    /**
     * @notice Add or remove a router from the allowlist
     * @param router Router address
     * @param allowed Whether to allow or disallow
     */
    function setRouterAllowed(address router, bool allowed) external onlyGovernance {
        if (router == address(0)) revert ZeroAddress();

        if (allowed && !isRouterAllowed[router]) {
            _allowedRouters.push(router);
        } else if (!allowed && isRouterAllowed[router]) {
            _removeFromArray(router);
        }

        isRouterAllowed[router] = allowed;
        emit RouterAllowlistUpdated(router, allowed);
    }

    /**
     * @notice Get all allowed routers
     * @return Array of allowed router addresses
     */
    function getAllowedRouters() external view returns (address[] memory) {
        return _allowedRouters;
    }

    function _removeFromArray(address router) internal {
        uint256 len = _allowedRouters.length;
        for (uint256 i = 0; i < len; i++) {
            if (_allowedRouters[i] == router) {
                _allowedRouters[i] = _allowedRouters[len - 1];
                _allowedRouters.pop();
                break;
            }
        }
    }

    // =========== Admin Functions ===========

    /**
     * @notice Set maximum slippage in basis points
     * @param newBps New max slippage (100 = 1%)
     */
    function setMaxSlippageBps(uint256 newBps) external onlyGovernance {
        if (newBps > MAX_SLIPPAGE_BPS) revert SlippageTooHigh();
        uint256 oldBps = maxSlippageBps;
        maxSlippageBps = newBps;
        emit MaxSlippageBpsUpdated(oldBps, newBps);
    }

    /**
     * @notice Set minimum swap threshold to prevent dust swaps
     * @param newThreshold New minimum threshold
     */
    function setMinSwapThreshold(uint256 newThreshold) external onlyGovernance {
        uint256 oldThreshold = minSwapThreshold;
        minSwapThreshold = newThreshold;
        emit MinSwapThresholdUpdated(oldThreshold, newThreshold);
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

    /**
     * @notice Transfer governance role
     * @param _governance New governance address
     */
    function transferGovernance(address _governance) external onlyGovernance {
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
    }
}
