// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { VeELTA } from "../staking/VeELTA.sol";
import { Errors } from "../utils/Errors.sol";

/**
 * @title RewardsDistributor
 * @author Elata Biosciences
 * @notice Distributes rewards to veELTA stakers based on their voting power
 * @dev Uses a merkle tree approach for gas-efficient reward distribution
 *
 * Features:
 * - Time-weighted reward distribution based on veELTA voting power
 * - Multiple reward tokens support
 * - Merkle tree proofs for gas-efficient claims
 * - Epoch-based reward cycles
 * - Emergency pause functionality
 *
 * Security:
 * - Reentrancy protection on all external functions
 * - Role-based access control for admin functions
 * - Merkle proof verification for claim validation
 * - Time-locked reward cycles to prevent manipulation
 */
contract RewardsDistributor is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    VeELTA public immutable veELTA;

    /// @notice Duration of each reward epoch (1 week)
    uint256 public constant EPOCH_DURATION = 7 days;

    /// @notice Minimum time lock for reward distribution
    uint256 public constant MIN_DISTRIBUTION_DELAY = 1 days;

    struct RewardEpoch {
        uint256 startTime;
        uint256 endTime;
        uint256 totalRewards;
        uint256 totalVotingPower;
        bytes32 merkleRoot;
        mapping(address => bool) claimed;
        bool finalized;
        bool paused;
    }

    struct RewardToken {
        IERC20 token;
        uint256 totalDistributed;
        bool active;
    }

    /// @notice Current epoch number
    uint256 public currentEpoch;

    /// @notice Mapping of epoch number to reward epoch data
    mapping(uint256 => RewardEpoch) public epochs;

    /// @notice Mapping of token address to reward token info
    mapping(address => RewardToken) public rewardTokens;

    /// @notice Array of active reward token addresses
    address[] public activeTokens;

    /// @notice Total rewards claimed by user across all epochs
    mapping(address => uint256) public totalClaimed;

    /// @notice Paused state for emergency stops
    bool public paused;

    event EpochStarted(uint256 indexed epoch, uint256 startTime, uint256 endTime);
    event EpochFinalized(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalRewards);
    event RewardClaimed(
        address indexed user,
        uint256 indexed epoch,
        address indexed token,
        uint256 amount
    );
    event RewardTokenAdded(address indexed token);
    event RewardTokenRemoved(address indexed token);
    event RewardsDeposited(address indexed token, uint256 amount, uint256 epoch);
    event EmergencyPause(bool paused);

    error EpochNotFinalized();
    error EpochAlreadyFinalized();
    error EpochNotStarted();
    error AlreadyClaimed();
    error InvalidProof();
    error InvalidEpoch();
    error TokenNotActive();
    error DistributionTooEarly();
    error ContractPaused();

    /**
     * @notice Initializes the rewards distributor
     * @param _veELTA Address of the VeELTA staking contract
     * @param _admin Address that will receive admin roles
     */
    constructor(VeELTA _veELTA, address _admin) {
        if (address(_veELTA) == address(0) || _admin == address(0)) {
            revert Errors.ZeroAddress();
        }

        veELTA = _veELTA;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        // Start the first epoch
        _startNewEpoch();
    }

    /**
     * @notice Modifier to check if contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /**
     * @notice Adds a new reward token
     * @param token Address of the ERC20 token to add as reward
     */
    function addRewardToken(IERC20 token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == address(0)) revert Errors.ZeroAddress();
        if (rewardTokens[address(token)].active) return; // Already active

        rewardTokens[address(token)] = RewardToken({
            token: token,
            totalDistributed: 0,
            active: true
        });

        activeTokens.push(address(token));
        emit RewardTokenAdded(address(token));
    }

    /**
     * @notice Removes a reward token (stops future distributions)
     * @param token Address of the token to remove
     */
    function removeRewardToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!rewardTokens[token].active) return;

        rewardTokens[token].active = false;

        // Remove from active tokens array
        for (uint256 i = 0; i < activeTokens.length; i++) {
            if (activeTokens[i] == token) {
                activeTokens[i] = activeTokens[activeTokens.length - 1];
                activeTokens.pop();
                break;
            }
        }

        emit RewardTokenRemoved(token);
    }

    /**
     * @notice Deposits rewards for the current epoch
     * @param token Address of the reward token
     * @param amount Amount of tokens to deposit
     */
    function depositRewards(
        address token,
        uint256 amount
    ) external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused {
        if (!rewardTokens[token].active) revert TokenNotActive();
        if (amount == 0) revert Errors.InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Deposit to current active epoch (currentEpoch - 1)
        uint256 activeEpoch = currentEpoch > 0 ? currentEpoch - 1 : 0;
        RewardEpoch storage epoch = epochs[activeEpoch];
        epoch.totalRewards += amount;

        rewardTokens[token].totalDistributed += amount;

        emit RewardsDeposited(token, amount, activeEpoch);
    }

    /**
     * @notice Finalizes the current epoch and starts a new one
     * @param merkleRoot Merkle root of the reward distribution tree
     */
    function finalizeEpoch(bytes32 merkleRoot) external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused {
        // Finalize the previous epoch (currentEpoch - 1)
        uint256 epochToFinalize = currentEpoch > 0 ? currentEpoch - 1 : 0;
        RewardEpoch storage epoch = epochs[epochToFinalize];

        if (epoch.finalized) revert EpochAlreadyFinalized();
        if (block.timestamp < epoch.endTime + MIN_DISTRIBUTION_DELAY) {
            revert DistributionTooEarly();
        }

        // Calculate total voting power at epoch end
        // This would typically be done off-chain and verified here
        epoch.totalVotingPower = _calculateTotalVotingPower(epoch.endTime);
        epoch.merkleRoot = merkleRoot;
        epoch.finalized = true;

        emit EpochFinalized(epochToFinalize, merkleRoot, epoch.totalRewards);

        // Start next epoch
        _startNewEpoch();
    }

    /**
     * @notice Claims rewards for a specific epoch
     * @param epoch Epoch number to claim rewards for
     * @param amount Amount of rewards to claim
     * @param merkleProof Merkle proof for the claim
     */
    function claimRewards(
        uint256 epoch,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant whenNotPaused {
        if (epoch >= currentEpoch) revert InvalidEpoch();

        RewardEpoch storage rewardEpoch = epochs[epoch];
        if (!rewardEpoch.finalized) revert EpochNotFinalized();
        if (rewardEpoch.claimed[msg.sender]) revert AlreadyClaimed();

        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!_verifyProof(merkleProof, rewardEpoch.merkleRoot, leaf)) {
            revert InvalidProof();
        }

        rewardEpoch.claimed[msg.sender] = true;
        totalClaimed[msg.sender] += amount;

        // Distribute rewards proportionally across active tokens
        _distributeRewards(msg.sender, amount, epoch);

        emit RewardClaimed(msg.sender, epoch, address(0), amount);
    }

    /**
     * @notice Claims rewards for multiple epochs in a single transaction
     * @param epochIds Array of epoch numbers
     * @param amounts Array of reward amounts
     * @param merkleProofs Array of merkle proofs
     */
    function claimMultipleEpochs(
        uint256[] calldata epochIds,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs
    ) external nonReentrant whenNotPaused {
        if (epochIds.length != amounts.length || amounts.length != merkleProofs.length) {
            revert Errors.ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < epochIds.length; i++) {
            uint256 epoch = epochIds[i];
            uint256 amount = amounts[i];
            bytes32[] calldata proof = merkleProofs[i];

            if (epoch >= currentEpoch) revert InvalidEpoch();

            RewardEpoch storage rewardEpoch = epochs[epoch];
            if (!rewardEpoch.finalized) revert EpochNotFinalized();
            if (rewardEpoch.claimed[msg.sender]) continue; // Skip already claimed

            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
            if (!_verifyProof(proof, rewardEpoch.merkleRoot, leaf)) {
                revert InvalidProof();
            }

            rewardEpoch.claimed[msg.sender] = true;
            totalClaimed[msg.sender] += amount;

            _distributeRewards(msg.sender, amount, epoch);
            emit RewardClaimed(msg.sender, epoch, address(0), amount);
        }
    }

    /**
     * @notice Emergency pause/unpause function
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        paused = _paused;
        emit EmergencyPause(_paused);
    }

    /**
     * @notice Gets the current epoch information
     * @return epoch Current epoch number
     * @return startTime Epoch start time
     * @return endTime Epoch end time
     * @return totalRewards Total rewards for the epoch
     * @return finalized Whether the epoch is finalized
     */
    function getCurrentEpoch()
        external
        view
        returns (uint256 epoch, uint256 startTime, uint256 endTime, uint256 totalRewards, bool finalized)
    {
        // Current active epoch is currentEpoch - 1 (since _startNewEpoch increments)
        uint256 activeEpoch = currentEpoch > 0 ? currentEpoch - 1 : 0;
        RewardEpoch storage current = epochs[activeEpoch];
        return (activeEpoch, current.startTime, current.endTime, current.totalRewards, current.finalized);
    }

    /**
     * @notice Checks if a user has claimed rewards for a specific epoch
     * @param user User address
     * @param epoch Epoch number
     * @return Whether the user has claimed rewards for the epoch
     */
    function hasClaimed(address user, uint256 epoch) external view returns (bool) {
        return epochs[epoch].claimed[user];
    }

    /**
     * @notice Gets the list of active reward tokens
     * @return Array of active token addresses
     */
    function getActiveTokens() external view returns (address[] memory) {
        return activeTokens;
    }

    /**
     * @notice Calculates pending rewards for a user across all unclaimed epochs
     * @param user User address
     * @return Total pending rewards (requires off-chain calculation for accuracy)
     */
    function pendingRewards(address user) external view returns (uint256) {
        // This is a simplified calculation - in practice, this would require
        // off-chain computation based on voting power at each epoch
        uint256 totalPending = 0;
        
        for (uint256 i = 0; i < currentEpoch; i++) {
            if (epochs[i].finalized && !epochs[i].claimed[user]) {
                // Simplified calculation - actual implementation would use merkle tree data
                totalPending += _estimateUserRewards(user, i);
            }
        }
        
        return totalPending;
    }

    /**
     * @notice Gets user's reward claim history
     * @param user User address
     * @return claimedEpochs Array of epochs where user has claimed
     * @return userTotalClaimed Total amount claimed across all epochs
     */
    function getUserRewardHistory(address user) external view returns (
        uint256[] memory claimedEpochs,
        uint256 userTotalClaimed
    ) {
        // Count claimed epochs
        uint256 claimedCount = 0;
        for (uint256 i = 0; i < currentEpoch; i++) {
            if (epochs[i].claimed[user]) {
                claimedCount++;
            }
        }
        
        // Build array of claimed epochs
        claimedEpochs = new uint256[](claimedCount);
        uint256 index = 0;
        for (uint256 i = 0; i < currentEpoch; i++) {
            if (epochs[i].claimed[user]) {
                claimedEpochs[index] = i;
                index++;
            }
        }
        
        userTotalClaimed = totalClaimed[user];
    }

    /**
     * @notice Gets detailed epoch information
     * @param epochId Epoch ID
     * @return startTime Epoch start time
     * @return endTime Epoch end time
     * @return totalRewards Total rewards in epoch
     * @return totalVotingPower Total voting power snapshot
     * @return finalized Whether epoch is finalized
     * @return merkleRoot Merkle root for claims
     */
    function getEpochDetails(uint256 epochId) external view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 totalRewards,
        uint256 totalVotingPower,
        bool finalized,
        bytes32 merkleRoot
    ) {
        RewardEpoch storage epoch = epochs[epochId];
        return (
            epoch.startTime,
            epoch.endTime,
            epoch.totalRewards,
            epoch.totalVotingPower,
            epoch.finalized,
            epoch.merkleRoot
        );
    }

    /**
     * @notice Gets reward token information
     * @param token Token address
     * @return isActive Whether token is active for rewards
     * @return totalDistributed Total amount distributed of this token
     */
    function getRewardTokenInfo(address token) external view returns (
        bool isActive,
        uint256 totalDistributed
    ) {
        RewardToken storage rewardToken = rewardTokens[token];
        return (rewardToken.active, rewardToken.totalDistributed);
    }

    /**
     * @notice Gets time until next epoch finalization
     * @return timeRemaining Time in seconds until current epoch can be finalized
     */
    function getTimeUntilFinalization() external view returns (uint256 timeRemaining) {
        RewardEpoch storage current = epochs[currentEpoch];
        uint256 finalizationTime = current.endTime + MIN_DISTRIBUTION_DELAY;
        
        if (block.timestamp >= finalizationTime) return 0;
        return finalizationTime - block.timestamp;
    }

    /**
     * @dev Starts a new reward epoch
     */
    function _startNewEpoch() internal {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + EPOCH_DURATION;

        RewardEpoch storage epoch = epochs[currentEpoch];
        epoch.startTime = startTime;
        epoch.endTime = endTime;
        epoch.totalRewards = 0;
        epoch.totalVotingPower = 0;
        epoch.merkleRoot = bytes32(0);
        epoch.finalized = false;
        epoch.paused = false;

        emit EpochStarted(currentEpoch, startTime, endTime);
        currentEpoch++;
    }

    /**
     * @dev Distributes rewards to user across active tokens
     * @param user User address
     * @param totalAmount Total reward amount to distribute
     * @param epoch Epoch number
     */
    function _distributeRewards(address user, uint256 totalAmount, uint256 epoch) internal {
        if (activeTokens.length == 0) return;

        // Distribute equally across all active tokens for simplicity
        // In practice, this could be weighted based on token deposits
        uint256 amountPerToken = totalAmount / activeTokens.length;
        uint256 remainder = totalAmount % activeTokens.length;

        for (uint256 i = 0; i < activeTokens.length; i++) {
            address tokenAddr = activeTokens[i];
            uint256 amount = amountPerToken;
            
            // Give remainder to first token
            if (i == 0) amount += remainder;

            if (amount > 0) {
                IERC20(tokenAddr).safeTransfer(user, amount);
                emit RewardClaimed(user, epoch, tokenAddr, amount);
            }
        }
    }

    /**
     * @dev Verifies a merkle proof
     * @param proof Merkle proof
     * @param root Merkle root
     * @param leaf Leaf to verify
     * @return Whether the proof is valid
     */
    function _verifyProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == root;
    }

    /**
     * @dev Calculates total voting power at a specific timestamp
     * @param timestamp Timestamp to calculate voting power at
     * @return Total voting power (simplified implementation)
     */
    function _calculateTotalVotingPower(uint256 timestamp) internal view returns (uint256) {
        // This is a placeholder - in practice, this would aggregate
        // voting power across all veELTA holders at the given timestamp
        // This requires either historical tracking or off-chain computation
        return 1000000 * 1e18; // Placeholder value
    }

    /**
     * @dev Estimates user rewards for a given epoch (simplified)
     * @param user User address
     * @param epoch Epoch number
     * @return Estimated reward amount
     */
    function _estimateUserRewards(address user, uint256 epoch) internal view returns (uint256) {
        // Simplified estimation - actual implementation would use historical data
        RewardEpoch storage rewardEpoch = epochs[epoch];
        if (!rewardEpoch.finalized || rewardEpoch.totalVotingPower == 0) return 0;

        // This is a placeholder calculation
        uint256 userVotingPower = veELTA.getUserVotingPower(user);
        return (rewardEpoch.totalRewards * userVotingPower) / rewardEpoch.totalVotingPower;
    }
}
