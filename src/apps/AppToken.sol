// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AppToken
 * @author Elata Biosciences
 * @notice Standard ERC20 token for individual apps in the Elata ecosystem
 * @dev No transfer taxes, fixed supply, minted to bonding curve for fair distribution
 *
 * Features:
 * - Standard ERC20 with burning capability
 * - No transfer fees for DEX compatibility
 * - Fixed supply minted once to bonding curve
 * - Role-based minting control
 * - Snapshot-compatible for future governance
 */
contract AppToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 private immutable _decimals;
    uint256 public immutable maxSupply;

    // App metadata
    string public appDescription;
    string public appImageURI;
    string public appWebsite;
    address public appCreator;

    event AppMetadataUpdated(string description, string imageURI, string website);

    error SupplyCapExceeded();
    error OnlyCreator();

    /**
     * @notice Initialize app token with metadata
     * @param name_ Token name (e.g., "NeuroGame Token")
     * @param symbol_ Token symbol (e.g., "NGT")
     * @param decimals_ Token decimals (typically 18)
     * @param maxSupply_ Maximum token supply
     * @param creator_ App creator address
     * @param admin_ Admin address (typically AppFactory)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        address creator_,
        address admin_
    ) ERC20(name_, symbol_) {
        require(creator_ != address(0) && admin_ != address(0), "Zero address");
        require(maxSupply_ > 0, "Invalid supply");

        _decimals = decimals_;
        maxSupply = maxSupply_;
        appCreator = creator_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint tokens to specified address (typically bonding curve)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > maxSupply) revert SupplyCapExceeded();
        _mint(to, amount);
    }

    /**
     * @notice Update app metadata (only creator)
     * @param description_ App description
     * @param imageURI_ App image URI
     * @param website_ App website URL
     */
    function updateMetadata(
        string calldata description_,
        string calldata imageURI_,
        string calldata website_
    ) external {
        if (msg.sender != appCreator) revert OnlyCreator();

        appDescription = description_;
        appImageURI = imageURI_;
        appWebsite = website_;

        emit AppMetadataUpdated(description_, imageURI_, website_);
    }

    /**
     * @notice Revoke minter role (makes supply fixed)
     * @param account Address to revoke minter role from
     */
    function revokeMinter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, account);
    }
}
