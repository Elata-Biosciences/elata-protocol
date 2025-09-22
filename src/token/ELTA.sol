// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title ELTA Token
 * @author Elata Biosciences
 * @notice The governance token for the Elata Protocol ecosystem
 * @dev Non-upgradeable ERC20 token with governance, permit, and burning capabilities
 *
 * Features:
 * - ERC20 standard with 18 decimals
 * - ERC20Votes for on-chain governance and delegation
 * - ERC20Permit for gasless approvals
 * - ERC20Burnable for deflationary mechanics
 * - AccessControl for role-based permissions
 * - Supply cap enforcement
 * - No transfer taxes or fees
 *
 * Security:
 * - Non-upgradeable for immutability
 * - Role-based minting permissions
 * - Immutable maximum supply cap
 * - Compatible with existing DeFi infrastructure
 */
contract ELTA is ERC20, ERC20Burnable, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public immutable MAX_SUPPLY;

    /**
     * @notice Initializes the ELTA token with specified parameters
     * @param name_ The name of the token (e.g., "ELTA")
     * @param symbol_ The symbol of the token (e.g., "ELTA")
     * @param admin_ The address that will receive admin and minter roles
     * @param initialRecipient The address that will receive the initial mint
     * @param initialMint The amount of tokens to mint initially (in wei)
     * @param maxSupply_ The maximum total supply cap (0 for no cap)
     * @dev Both admin_ and initialRecipient must be non-zero addresses
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address admin_,
        address initialRecipient,
        uint256 initialMint,
        uint256 maxSupply_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (admin_ == address(0) || initialRecipient == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);

        MAX_SUPPLY = maxSupply_;

        if (initialMint > 0) {
            _mint(initialRecipient, initialMint);
        }
    }

    /**
     * @notice Returns the number of decimal places for the token
     * @return The number of decimals (always 18 for ELTA)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Mints new tokens to the specified address
     * @param to The address to receive the newly minted tokens
     * @param amount The amount of tokens to mint (in wei)
     * @dev Only addresses with MINTER_ROLE can call this function
     * @dev Respects the MAX_SUPPLY cap if set (non-zero)
     * @dev Will revert if minting would exceed the maximum supply
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert Errors.ZeroAddress();
        _mint(to, amount);
    }

    /**
     * @dev Internal function to handle token transfers, minting, and burning
     * @param from The address tokens are transferred from (zero for minting)
     * @param to The address tokens are transferred to (zero for burning)
     * @param value The amount of tokens to transfer/mint/burn
     * @dev Enforces supply cap when minting (from == address(0))
     * @dev Updates vote checkpoints for governance functionality
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        if (from == address(0)) {
            // Minting: check supply cap
            if (MAX_SUPPLY != 0 && (totalSupply() + value > MAX_SUPPLY)) {
                revert Errors.CapExceeded();
            }
        }
        super._update(from, to, value);
    }

    /**
     * @notice Returns the current nonce for the given owner
     * @param owner The address to get the nonce for
     * @return The current nonce value
     * @dev Required override due to multiple inheritance from ERC20Permit and Nonces
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
