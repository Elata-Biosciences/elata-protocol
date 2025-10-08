// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AppToken
 * @author Elata Biosciences
 * @notice Standard ERC20 token for individual apps in the Elata ecosystem
 * @dev No transfer taxes, fixed supply, minted to bonding curve for fair distribution
 *
 * Features:
 * - Standard ERC20 with burning capability and permit support
 * - No transfer fees for DEX compatibility
 * - Optional supply cap with finalizeMinting() for permanent lock
 * - Role-based minting control
 * - Gasless approvals via ERC20Permit
 * - App metadata storage
 */
contract AppToken is ERC20, ERC20Burnable, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 private immutable _decimals;
    uint256 public immutable maxSupply;
    
    /// @notice Whether minting has been finalized (irreversible)
    bool public mintingFinalized;

    // App metadata
    string public appDescription;
    string public appImageURI;
    string public appWebsite;
    address public appCreator;

    event AppMetadataUpdated(string description, string imageURI, string website);
    event MintingFinalized();
    event Minted(address indexed to, uint256 amount);

    error SupplyCapExceeded();
    error OnlyCreator();
    error MintingAlreadyFinalized();

    /**
     * @notice Initialize app token with metadata
     * @param name_ Token name (e.g., "NeuroGame Token")
     * @param symbol_ Token symbol (e.g., "NGT")
     * @param decimals_ Token decimals (typically 18)
     * @param maxSupply_ Maximum token supply (0 = uncapped until finalize)
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
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
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
     * @notice Returns the app creator (compatible with IOwnable)
     * @return Address of the app creator
     */
    function owner() public view returns (address) {
        return appCreator;
    }

    /**
     * @notice Mint tokens to specified address (typically bonding curve)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (mintingFinalized) revert MintingAlreadyFinalized();
        if (maxSupply > 0 && totalSupply() + amount > maxSupply) revert SupplyCapExceeded();
        
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Permanently disable further minting
     * @dev Irreversible operation - locks supply forever
     */
    function finalizeMinting() external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintingFinalized = true;
        emit MintingFinalized();
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
