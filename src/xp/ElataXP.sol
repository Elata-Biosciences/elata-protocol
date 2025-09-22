// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title ElataXP
 * @notice Non-transferable on-chain XP points with checkpoint/snapshot support via ERC20Votes.
 *         - Only MINTER can mint/burn.
 *         - Transfers disabled (soulbound-like).
 *         - Uses ERC20Votes checkpoints for historical balance queries.
 *
 * Notes:
 * - Uses ERC20Votes checkpoint system instead of deprecated ERC20Snapshot
 * - Decay/expiry can be added later (global epoch math or keeper-driven).
 * - Self-delegation is required to enable checkpoint tracking per user.
 */
contract ElataXP is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant XP_MINTER_ROLE = keccak256("XP_MINTER_ROLE");

    constructor(address admin) ERC20("Elata XP", "ELTAXP") ERC20Permit("Elata XP") {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(XP_MINTER_ROLE, admin);
    }

    function decimals() public pure override returns (uint8) {
        return 18; // points with 18 decimals; change to 0 if you want integer-only
    }

    /// @notice Mint XP to `to`. Only XP_MINTER_ROLE.
    function award(address to, uint256 amount) external onlyRole(XP_MINTER_ROLE) {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();
        _mint(to, amount);

        // Auto-delegate to self to enable checkpoint tracking
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        }
    }

    /// @notice Burn XP from `from`. Only XP_MINTER_ROLE (acts as slasher/revoker).
    function revoke(address from, uint256 amount) external onlyRole(XP_MINTER_ROLE) {
        if (from == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();
        _burn(from, amount);
    }

    /// @notice Get past votes (XP balance) at a specific timepoint (block number).
    function getPastXP(address account, uint256 timepoint) external view returns (uint256) {
        return getPastVotes(account, timepoint);
    }

    /// @dev Disable transfers; allow only mint/burn (from/to zero address).
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        if (from != address(0) && to != address(0)) revert Errors.TransfersDisabled();
        super._update(from, to, value);
    }

    // Required overrides for Solidity
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
