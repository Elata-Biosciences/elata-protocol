// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title ElataXP
 * @author Elata Biosciences
 * @notice Non-transferable experience points token for the Elata ecosystem.
 * @dev ERC20 with no transfers allowed. Supports role-based mint/burn and off-chain signature-based awards.
 * Extends ERC20Votes for governance integration (XP can be used for voting weight).
 */
contract ElataXP is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant XP_OPERATOR_ROLE = keccak256("XP_OPERATOR_ROLE");

    // Track operator nonces for signature-based XP updates (one nonce per operator address).
    mapping(address => uint256) public operatorNonces;

    // EIP-712 typehash for struct used in updateBySig (off-chain XP award authorization).
    bytes32 public constant XPUPDATE_TYPEHASH = keccak256(
        "XPUpdate(address operator,address user,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    // Events for minting and burning XP:
    event XPAwarded(address indexed user, uint256 amount);
    event XPRevoked(address indexed user, uint256 amount);

    /**
     * @notice Constructor to initialize XP token.
     * @param admin The address that will have the default admin role and operator role initially.
     */
    constructor(address admin) ERC20("Elata XP", "XP") ERC20Permit("Elata XP") {
        if (admin == address(0)) revert Errors.ZeroAddress();
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(XP_OPERATOR_ROLE, admin);
    }

    /**
     * @notice Override decimals to 18 (standard).
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // ========== XP Minting/Burning by Authorized Operators ==========

    /**
     * @notice Award (mint) XP to a user.
     * @param to The address to receive the XP.
     * @param amount The amount of XP to mint.
     * @dev Only callable by an address with XP_OPERATOR_ROLE.
     */
    function award(address to, uint256 amount) external onlyRole(XP_OPERATOR_ROLE) {
        if (to == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();

        _mint(to, amount);

        // Auto-delegate to self to enable checkpoint tracking
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        }

        emit XPAwarded(to, amount);
    }

    /**
     * @notice Revoke (burn) XP from a user.
     * @param from The address from which to burn XP.
     * @param amount The amount of XP to burn.
     * @dev Only callable by an address with XP_OPERATOR_ROLE.
     */
    function revoke(address from, uint256 amount) external onlyRole(XP_OPERATOR_ROLE) {
        if (from == address(0)) revert Errors.ZeroAddress();
        if (amount == 0) revert Errors.InvalidAmount();
        _burn(from, amount);
        emit XPRevoked(from, amount);
    }

    // ========== Off-Chain Signature-Based XP Award ==========

    /**
     * @notice Claim an XP award using an operator's signed authorization (EIP-712).
     * @param operator The operator who signed the XP award.
     * @param user The user address to receive XP.
     * @param amount The amount of XP to award.
     * @param deadline Expiration timestamp for this signature (Unix time).
     * @param v Sig v component.
     * @param r Sig r component.
     * @param s Sig s component.
     * @dev Anyone can call this (typically the user), but it requires a valid signature from an authorized operator.
     * The operator must have XP_OPERATOR_ROLE. The signature is one-time use per operator (nonce is consumed).
     */
    function updateBySig(
        address operator,
        address user,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert Errors.SignatureExpired();
        if (amount == 0 || user == address(0) || operator == address(0)) {
            revert Errors.InvalidAmount();
        }

        // Construct the struct hash and message digest as per EIP-712
        uint256 currentNonce = operatorNonces[operator];
        bytes32 structHash =
            keccak256(abi.encode(XPUPDATE_TYPEHASH, operator, user, amount, currentNonce, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);

        // Recover the signer
        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != operator || !hasRole(XP_OPERATOR_ROLE, operator)) {
            revert Errors.InvalidSignature();
        }

        // Use up this signature nonce
        operatorNonces[operator] = currentNonce + 1;

        // Mint the XP to user
        _mint(user, amount);
        emit XPAwarded(user, amount);
    }

    // ========== View Functions ==========

    /**
     * @notice Gets past XP balance at a specific block (for voting/snapshot integration)
     * @param account User address
     * @param timepoint Block number
     * @return XP balance at the specified block
     */
    function getPastXP(address account, uint256 timepoint) external view returns (uint256) {
        return getPastVotes(account, timepoint);
    }

    // ========== Non-Transferable Enforcement ==========

    /**
     * @dev Override to disable transfers (soulbound)
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        if (from != address(0) && to != address(0)) revert Errors.TransfersDisabled();
        super._update(from, to, value);
    }

    /**
     * @dev Required override for multiple inheritance
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
