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
 * @dev Includes 1% transfer fee (configurable, capped at 2%) with 70/15/15 split
 *
 * Features:
 * - Standard ERC20 with burning capability and permit support
 * - 1% transfer fee (default) routed to app stakers, veELTA, and treasury
 * - Exemption system for bonding curve, vault, and other protocol contracts
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

    // Transfer fee configuration
    uint16 public transferFeeBps = 100; // 1%, governance-configurable
    uint16 public constant MAX_TRANSFER_FEE_BPS = 200; // 2% max
    address public governance;
    mapping(address => bool) public transferFeeExempt;

    // Reward distributor addresses
    address public appRewardsDistributor;
    address public rewardsDistributor;
    address public treasury;
    address public appVault; // Store vault for exemption

    event AppMetadataUpdated(string description, string imageURI, string website);
    event MintingFinalized();
    event Minted(address indexed to, uint256 amount);
    event TransferFeeUpdated(uint16 oldBps, uint16 newBps);
    event TransferFeeExemptSet(address indexed account, bool exempt);
    event TransferFeeCollected(
        address indexed from,
        address indexed to,
        uint256 totalFee,
        uint256 appFee,
        uint256 veFee,
        uint256 treasuryFee
    );

    error SupplyCapExceeded();
    error OnlyCreator();
    error MintingAlreadyFinalized();
    error FeeTooHigh();
    error OnlyGovernance();
    error VaultAlreadySet();

    /**
     * @notice Initialize app token with metadata
     * @param name_ Token name (e.g., "NeuroGame Token")
     * @param symbol_ Token symbol (e.g., "NGT")
     * @param decimals_ Token decimals (typically 18)
     * @param maxSupply_ Maximum token supply (0 = uncapped until finalize)
     * @param creator_ App creator address
     * @param admin_ Admin address (typically AppFactory)
     * @param governance_ Governance address for fee configuration
     * @param appRewardsDistributor_ App rewards distributor address
     * @param rewardsDistributor_ Main rewards distributor address
     * @param treasury_ Treasury address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        address creator_,
        address admin_,
        address governance_,
        address appRewardsDistributor_,
        address rewardsDistributor_,
        address treasury_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(creator_ != address(0) && admin_ != address(0), "Zero address");
        require(governance_ != address(0), "Zero governance");
        require(appRewardsDistributor_ != address(0), "Zero app rewards");
        require(rewardsDistributor_ != address(0), "Zero rewards");
        require(treasury_ != address(0), "Zero treasury");
        require(maxSupply_ > 0, "Invalid supply");

        _decimals = decimals_;
        maxSupply = maxSupply_;
        appCreator = creator_;
        governance = governance_;
        appRewardsDistributor = appRewardsDistributor_;
        rewardsDistributor = rewardsDistributor_;
        treasury = treasury_;

        // Set initial exemptions
        transferFeeExempt[address(this)] = true;
        transferFeeExempt[admin_] = true; // factory

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

    /**
     * @notice Set the app vault address (called by factory after vault creation)
     * @param _vault Vault address
     */
    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (appVault != address(0)) revert VaultAlreadySet();
        require(_vault != address(0), "Zero vault");
        appVault = _vault;
        transferFeeExempt[_vault] = true;
    }

    /**
     * @notice Set transfer fee in basis points (governance only)
     * @param newBps New fee rate (0-200 = 0-2%)
     */
    function setTransferFeeBps(uint16 newBps) external {
        if (msg.sender != governance) revert OnlyGovernance();
        if (newBps > MAX_TRANSFER_FEE_BPS) revert FeeTooHigh();
        emit TransferFeeUpdated(transferFeeBps, newBps);
        transferFeeBps = newBps;
    }

    /**
     * @notice Set transfer fee exemption status (governance only)
     * @param account Address to update
     * @param exempt True to exempt from fees
     */
    function setTransferFeeExempt(address account, bool exempt) external {
        if (msg.sender != governance && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert OnlyGovernance();
        }
        transferFeeExempt[account] = exempt;
        emit TransferFeeExemptSet(account, exempt);
    }

    /**
     * @notice Get transfer fee info for caller
     * @return feeBps Current fee rate in basis points
     * @return maxFeeBps Maximum allowed fee rate
     * @return isExempt Whether caller is exempt from fees
     */
    function getTransferFeeInfo()
        external
        view
        returns (uint16 feeBps, uint16 maxFeeBps, bool isExempt)
    {
        feeBps = transferFeeBps;
        maxFeeBps = MAX_TRANSFER_FEE_BPS;
        isExempt = transferFeeExempt[msg.sender];
    }

    /**
     * @notice Calculate transfer fee for a given amount
     * @param amount Transfer amount
     * @return fee Fee amount
     * @return netAmount Amount after fee
     */
    function calculateTransferFee(uint256 amount)
        external
        view
        returns (uint256 fee, uint256 netAmount)
    {
        fee = (amount * transferFeeBps) / 10_000;
        netAmount = amount - fee;
    }

    /**
     * @dev Override _update to implement fee-on-transfer with 70/15/15 split
     */
    function _update(address from, address to, uint256 amount) internal override {
        // Skip fee for mints, burns, and exempt addresses
        if (
            from == address(0) || to == address(0) || transferFeeExempt[from]
                || transferFeeExempt[to] || transferFeeBps == 0
        ) {
            super._update(from, to, amount);
            return;
        }

        // Calculate and distribute fee
        uint256 fee = (amount * transferFeeBps) / 10_000;
        uint256 netAmount = amount - fee;

        // Transfer net amount to recipient
        super._update(from, to, netAmount);

        // Split fee 70/15/15
        uint256 appFee = (fee * 7000) / 10_000;
        uint256 veFee = (fee * 1500) / 10_000;
        uint256 treasuryFee = fee - appFee - veFee; // Avoid rounding issues

        // Distribute fees (from sender to distributors)
        if (appFee > 0) {
            super._update(from, appRewardsDistributor, appFee);
        }
        if (veFee > 0) {
            super._update(from, rewardsDistributor, veFee);
        }
        if (treasuryFee > 0) {
            super._update(from, treasury, treasuryFee);
        }

        emit TransferFeeCollected(from, to, fee, appFee, veFee, treasuryFee);
    }
}
