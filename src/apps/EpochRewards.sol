// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EpochRewards
 * @author Elata Protocol
 * @notice Time-boxed, owner-funded distributions with Merkle claims
 * @dev Avoids continuous faucets by using discrete epochs
 *
 * Key Features:
 * - Owner-funded epochs (no continuous minting)
 * - Time-boxed distributions
 * - Merkle proof claims for gas efficiency
 * - Per-epoch isolation
 * - Off-chain XP → on-chain claim flow
 *
 * Epoch Flow:
 * 1. Owner starts epoch with time window
 * 2. Owner funds epoch with app tokens
 * 3. Off-chain: compute rankings/XP, generate Merkle tree
 * 4. Owner finalizes epoch with Merkle root
 * 5. Users claim rewards with proofs
 */
contract EpochRewards is Ownable, ReentrancyGuard {
    /// @notice App token used for rewards
    IERC20 public immutable APP;

    struct Epoch {
        uint64 start; // Epoch start time
        uint64 end; // Epoch end time (0 = no end)
        bytes32 merkleRoot; // Root of winners tree
        uint256 totalFunded; // Total tokens funded
        uint256 totalClaimed; // Total tokens claimed
    }

    /// @notice Current epoch ID (increments on startEpoch)
    uint256 public epochId;

    /// @notice Epoch data by ID
    mapping(uint256 => Epoch) public epochs;

    /// @notice Claim status per epoch per user
    mapping(uint256 => mapping(address => bool)) public claimed;

    event EpochStarted(uint256 indexed id, uint64 start, uint64 end);
    event EpochFunded(uint256 indexed id, uint256 amount);
    event EpochFinalized(uint256 indexed id, bytes32 root);
    event Claimed(uint256 indexed id, address indexed user, uint256 amount);

    error InvalidWindow();
    error NoActiveEpoch();
    error AlreadyFinalized();
    error NotFinalized();
    error AlreadyClaimed();
    error InvalidProof();

    /**
     * @notice Initialize epoch rewards contract
     * @param appToken App token address
     * @param owner_ Contract owner (app creator)
     */
    constructor(address appToken, address owner_) Ownable(owner_) {
        APP = IERC20(appToken);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EPOCH MANAGEMENT
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Start a new epoch
     * @param start Epoch start time
     * @param end Epoch end time (0 = no end)
     */
    function startEpoch(uint64 start, uint64 end) external onlyOwner {
        if (end != 0 && end <= start) revert InvalidWindow();

        epochId += 1;
        epochs[epochId] =
            Epoch({ start: start, end: end, merkleRoot: 0, totalFunded: 0, totalClaimed: 0 });

        emit EpochStarted(epochId, start, end);
    }

    /**
     * @notice Fund current epoch with tokens
     * @dev Owner must approve this contract first
     * @param amount Amount of tokens to fund
     */
    function fund(uint256 amount) external onlyOwner {
        if (epochId == 0) revert NoActiveEpoch();

        APP.transferFrom(msg.sender, address(this), amount);
        epochs[epochId].totalFunded += amount;

        emit EpochFunded(epochId, amount);
    }

    /**
     * @notice Finalize current epoch with Merkle root
     * @dev Enables claims for this epoch
     * @param merkleRoot Root of (address, amount) tree
     */
    function finalizeEpoch(bytes32 merkleRoot) external onlyOwner {
        if (epochId == 0) revert NoActiveEpoch();
        if (epochs[epochId].merkleRoot != 0) revert AlreadyFinalized();

        epochs[epochId].merkleRoot = merkleRoot;
        emit EpochFinalized(epochId, merkleRoot);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CLAIMS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Claim rewards for a specific epoch
     * @param id Epoch ID
     * @param proof Merkle proof of (msg.sender, amount)
     * @param amount Reward amount
     */
    function claim(uint256 id, bytes32[] calldata proof, uint256 amount) external nonReentrant {
        Epoch storage e = epochs[id];

        if (e.merkleRoot == 0) revert NotFinalized();
        if (claimed[id][msg.sender]) revert AlreadyClaimed();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!MerkleProof.verify(proof, e.merkleRoot, leaf)) {
            revert InvalidProof();
        }

        claimed[id][msg.sender] = true;
        e.totalClaimed += amount;
        APP.transfer(msg.sender, amount);

        emit Claimed(id, msg.sender, amount);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ENHANCED VIEW FUNCTIONS
    // ────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Get current active epoch ID
     * @return Current epoch ID (0 if none)
     */
    function getCurrentEpochId() external view returns (uint256) {
        return epochId;
    }

    /**
     * @notice Check if epoch is claimable
     * @param id Epoch ID
     * @return isClaimable Whether epoch can be claimed
     */
    function isEpochClaimable(uint256 id) external view returns (bool) {
        return epochs[id].merkleRoot != 0;
    }

    /**
     * @notice Get epoch utilization
     * @param id Epoch ID
     * @return utilizationBps Percentage of funded amount claimed (in bps)
     */
    function getEpochUtilization(uint256 id) external view returns (uint256 utilizationBps) {
        Epoch memory e = epochs[id];
        if (e.totalFunded == 0) return 0;
        return (e.totalClaimed * 10000) / e.totalFunded;
    }

    /**
     * @notice Batch get epochs
     * @param ids Array of epoch IDs
     * @return epochList Array of epochs
     */
    function getEpochs(uint256[] calldata ids) external view returns (Epoch[] memory epochList) {
        epochList = new Epoch[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            epochList[i] = epochs[ids[i]];
        }
    }

    /**
     * @notice Check multiple claim statuses at once
     * @param id Epoch ID
     * @param users Array of user addresses
     * @return statuses Array of claim statuses
     */
    function checkClaimStatuses(uint256 id, address[] calldata users)
        external
        view
        returns (bool[] memory statuses)
    {
        statuses = new bool[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            statuses[i] = claimed[id][users[i]];
        }
    }
}
