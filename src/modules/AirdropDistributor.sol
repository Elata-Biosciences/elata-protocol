// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AirdropDistributor
 * @author Elata Biosciences
 * @notice Merkle-based airdrop distributor for ecosystem pool tokens
 * @dev Supports multiple campaigns with per-campaign Merkle roots
 *
 * Per Protocol Changes document section 10.2:
 * - Ecosystem pool distributed via Merkle airdrops
 * - Developer incentives from ecosystem vault
 *
 * Key Features:
 * - Multiple campaigns per contract
 * - Per-campaign Merkle root
 * - Double-claim protection
 * - Campaign deactivation for emergencies
 * - Token rescue for unclaimed amounts
 *
 * Security:
 * - ReentrancyGuard on claims
 * - Admin-only campaign management
 * - Operator role for campaign creation
 */
contract AirdropDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========== Errors ===========
    error ZeroAddress();
    error InvalidRoot();
    error InvalidProof();
    error AlreadyClaimed();
    error CampaignInactive();
    error Unauthorized();

    // =========== Events ===========
    event CampaignCreated(
        uint256 indexed campaignId, uint256 indexed appId, address token, bytes32 merkleRoot, string name
    );
    event Claimed(uint256 indexed campaignId, address indexed account, uint256 amount);
    event CampaignDeactivated(uint256 indexed campaignId);
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // =========== Structs ===========
    struct Campaign {
        uint256 appId;
        address token;
        bytes32 merkleRoot;
        string name;
        uint256 totalClaimed;
        bool active;
    }

    // =========== State ===========

    /// @notice Admin address
    address public admin;

    /// @notice Operator who can create campaigns
    address public operator;

    /// @notice All campaigns
    Campaign[] public campaigns;

    /// @notice Whether an address has claimed from a campaign
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // =========== Constructor ===========

    /**
     * @notice Create a new airdrop distributor
     * @param _admin Admin address
     * @param _operator Operator address who can create campaigns
     */
    constructor(address _admin, address _operator) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();

        admin = _admin;
        operator = _operator;
    }

    // =========== Modifiers ===========

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlyOperatorOrAdmin() {
        if (msg.sender != operator && msg.sender != admin) revert Unauthorized();
        _;
    }

    // =========== Campaign Management ===========

    /**
     * @notice Create a new airdrop campaign
     * @param _appId App ID this campaign is for
     * @param _token Token to distribute
     * @param _merkleRoot Merkle root of (address, amount) pairs
     * @param _name Campaign name for display
     * @return campaignId ID of the created campaign
     */
    function createCampaign(uint256 _appId, address _token, bytes32 _merkleRoot, string calldata _name)
        external
        onlyOperatorOrAdmin
        returns (uint256 campaignId)
    {
        if (_token == address(0)) revert ZeroAddress();
        if (_merkleRoot == bytes32(0)) revert InvalidRoot();

        campaignId = campaigns.length;

        campaigns.push(
            Campaign({
                appId: _appId, token: _token, merkleRoot: _merkleRoot, name: _name, totalClaimed: 0, active: true
            })
        );

        emit CampaignCreated(campaignId, _appId, _token, _merkleRoot, _name);
    }

    /**
     * @notice Deactivate a campaign (emergency stop)
     * @param _campaignId Campaign ID to deactivate
     */
    function deactivateCampaign(uint256 _campaignId) external onlyAdmin {
        campaigns[_campaignId].active = false;
        emit CampaignDeactivated(_campaignId);
    }

    // =========== Claim Functions ===========

    /**
     * @notice Claim airdrop tokens
     * @param _campaignId Campaign to claim from
     * @param _amount Amount to claim
     * @param _proof Merkle proof
     */
    function claim(uint256 _campaignId, uint256 _amount, bytes32[] calldata _proof) external nonReentrant {
        Campaign storage campaign = campaigns[_campaignId];

        if (!campaign.active) revert CampaignInactive();
        if (hasClaimed[_campaignId][msg.sender]) revert AlreadyClaimed();

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        if (!MerkleProof.verify(_proof, campaign.merkleRoot, leaf)) {
            revert InvalidProof();
        }

        // Mark as claimed
        hasClaimed[_campaignId][msg.sender] = true;
        campaign.totalClaimed += _amount;

        // Transfer tokens
        IERC20(campaign.token).safeTransfer(msg.sender, _amount);

        emit Claimed(_campaignId, msg.sender, _amount);
    }

    // =========== Admin Functions ===========

    /**
     * @notice Set operator address
     * @param _operator New operator address
     */
    function setOperator(address _operator) external onlyAdmin {
        if (_operator == address(0)) revert ZeroAddress();
        address oldOperator = operator;
        operator = _operator;
        emit OperatorUpdated(oldOperator, _operator);
    }

    /**
     * @notice Transfer admin role
     * @param _admin New admin address
     */
    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin = _admin;
        emit AdminUpdated(oldAdmin, _admin);
    }

    /**
     * @notice Rescue tokens from the contract
     * @param _token Token to rescue
     * @param _to Recipient address
     * @param _amount Amount to rescue
     */
    function rescueTokens(address _token, address _to, uint256 _amount) external onlyAdmin {
        if (_to == address(0)) revert ZeroAddress();
        IERC20(_token).safeTransfer(_to, _amount);
        emit TokensRescued(_token, _to, _amount);
    }

    // =========== View Functions ===========

    /**
     * @notice Get campaign details
     * @param _campaignId Campaign ID
     * @return appId App ID
     * @return token Token address
     * @return merkleRoot Merkle root
     * @return name Campaign name
     * @return totalClaimed Total amount claimed
     * @return active Whether campaign is active
     */
    function getCampaign(uint256 _campaignId)
        external
        view
        returns (
            uint256 appId,
            address token,
            bytes32 merkleRoot,
            string memory name,
            uint256 totalClaimed,
            bool active
        )
    {
        Campaign storage campaign = campaigns[_campaignId];
        return
            (campaign.appId, campaign.token, campaign.merkleRoot, campaign.name, campaign.totalClaimed, campaign.active);
    }

    /**
     * @notice Get total number of campaigns
     * @return Number of campaigns
     */
    function campaignCount() external view returns (uint256) {
        return campaigns.length;
    }
}
