// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AppEcosystemVault
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Simple custody contract holding an app's ecosystem token allocation for airdrops and initiatives.
 * @dev Receives 25% of app token supply at launch. The admin may withdraw tokens to AirdropDistributor
 *      or other destinations. All movements emit events for transparency. The admin role is transferable.
 */
contract AppEcosystemVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized();
    error InsufficientBalance();

    // =========== Events ===========
    event TokensWithdrawn(address indexed token, address indexed to, uint256 amount);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    // =========== State ===========

    /// @notice App ID this vault belongs to
    uint256 public immutable appId;

    /// @notice Primary token held in vault
    address public immutable token;

    /// @notice Admin who can withdraw tokens
    address public admin;

    // =========== Constructor ===========

    /**
     * @notice Create a new ecosystem vault
     * @param _appId App ID for metadata attribution
     * @param _token Primary token held in vault
     * @param _admin Admin address who can withdraw
     */
    constructor(uint256 _appId, address _token, address _admin) {
        if (_token == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        appId = _appId;
        token = _token;
        admin = _admin;
    }

    // =========== Core Functions ===========

    /**
     * @notice Withdraw tokens to a destination
     * @param to Destination address (e.g., AirdropDistributor)
     * @param amount Amount to withdraw
     * @dev Only callable by admin
     */
    function withdraw(address to, uint256 amount) external nonReentrant {
        if (msg.sender != admin) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance < amount) revert InsufficientBalance();

        IERC20(token).safeTransfer(to, amount);

        emit TokensWithdrawn(token, to, amount);
    }

    /**
     * @notice Withdraw any ERC20 token (for emergency recovery)
     * @param tokenAddr Token to withdraw
     * @param to Destination address
     * @param amount Amount to withdraw
     * @dev Only callable by admin
     */
    function withdrawAny(address tokenAddr, address to, uint256 amount) external nonReentrant {
        if (msg.sender != admin) revert Unauthorized();
        if (tokenAddr == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 tokenBalance = IERC20(tokenAddr).balanceOf(address(this));
        if (tokenBalance < amount) revert InsufficientBalance();

        IERC20(tokenAddr).safeTransfer(to, amount);

        emit TokensWithdrawn(tokenAddr, to, amount);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Transfer admin role
     * @param _newAdmin New admin address
     * @dev Only callable by current admin
     */
    function setAdmin(address _newAdmin) external {
        if (msg.sender != admin) revert Unauthorized();
        if (_newAdmin == address(0)) revert ZeroAddress();

        address oldAdmin = admin;
        admin = _newAdmin;

        emit AdminUpdated(oldAdmin, _newAdmin);
    }

    // =========== View Functions ===========

    /**
     * @notice Get current token balance
     * @return Current balance of primary token
     */
    function balance() external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get balance of any token
     * @param tokenAddr Token to check
     * @return Current balance
     */
    function balanceOf(address tokenAddr) external view returns (uint256) {
        return IERC20(tokenAddr).balanceOf(address(this));
    }
}
