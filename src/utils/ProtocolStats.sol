// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ELTA } from "../token/ELTA.sol";
import { VeELTA } from "../staking/VeELTA.sol";
import { ElataXP } from "../experience/ElataXP.sol";
import { LotPool } from "../governance/LotPool.sol";
import { RewardsDistributor } from "../rewards/RewardsDistributor.sol";

/**
 * @title ProtocolStats
 * @author Elata Biosciences
 * @notice Comprehensive statistics and data aggregation for frontend integration
 * @dev Provides batch queries and aggregated data for efficient frontend loading
 */
contract ProtocolStats {
    ELTA public immutable elta;
    VeELTA public immutable staking;
    ElataXP public immutable xp;
    LotPool public immutable funding;
    RewardsDistributor public immutable rewards;

    struct UserSummary {
        uint256 eltaBalance;
        uint256 eltaVotingPower;
        uint256 xpBalance;
        uint256 stakingPositions;
        uint256 totalStaked;
        uint256 totalVotingPower;
        uint256 pendingRewards;
        uint256 totalClaimedRewards;
    }

    struct PositionSummary {
        uint256 tokenId;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 votingPower;
        address delegate;
        bool isExpired;
        bool emergencyUnlocked;
        uint256 timeRemaining;
    }

    struct ProtocolSummary {
        uint256 totalValueLocked;
        uint256 totalXPIssued;
        uint256 totalActivePositions;
        uint256 averageLockDuration;
        uint256 totalRewardsDistributed;
        uint256 currentFundingRound;
        uint256 totalFundingAllocated;
    }

    constructor(
        ELTA _elta,
        VeELTA _staking,
        ElataXP _xp,
        LotPool _funding,
        RewardsDistributor _rewards
    ) {
        elta = _elta;
        staking = _staking;
        xp = _xp;
        funding = _funding;
        rewards = _rewards;
    }

    /**
     * @notice Gets comprehensive user summary for dashboard
     * @param user User address
     * @return Complete user data summary
     */
    function getUserSummary(address user) external view returns (UserSummary memory) {
        return UserSummary({
            eltaBalance: elta.balanceOf(user),
            eltaVotingPower: elta.getVotes(user),
            xpBalance: xp.balanceOf(user),
            stakingPositions: staking.balanceOf(user),
            totalStaked: _getTotalStaked(user),
            totalVotingPower: staking.balanceOf(user),
            pendingRewards: rewards.estimatePendingVeRewards(user),
            totalClaimedRewards: 0 // No longer tracked globally in new architecture
         });
    }

    /**
     * @notice Gets detailed information about user's lock position
     * @dev Each user has one lock position
     * @param user User address
     * @return Array of position summaries (single element or empty)
     */
    function getUserPositions(address user) external view returns (PositionSummary[] memory) {
        // Single lock per user
        (uint256 principal, uint64 unlockTime, uint256 veBalance, bool isExpired) =
            staking.getLockDetails(user);

        if (principal == 0) {
            return new PositionSummary[](0);
        }

        PositionSummary[] memory positions = new PositionSummary[](1);
        positions[0] = PositionSummary({
            tokenId: 0, // No tokenId (ERC20 model, not NFT)
            amount: principal,
            startTime: 0, // Not tracked
            endTime: unlockTime,
            votingPower: veBalance,
            delegate: user, // Self-delegation
            isExpired: isExpired,
            emergencyUnlocked: false, // Not tracked
            timeRemaining: isExpired ? 0 : (unlockTime - uint64(block.timestamp))
        });

        return positions;
    }

    /**
     * @notice Gets comprehensive protocol statistics
     * @return Protocol-wide metrics
     */
    function getProtocolSummary() external view returns (ProtocolSummary memory) {
        return ProtocolSummary({
            totalValueLocked: _calculateTotalValueLocked(),
            totalXPIssued: xp.totalSupply(),
            totalActivePositions: staking.totalSupply(),
            averageLockDuration: _calculateAverageLockDuration(),
            totalRewardsDistributed: _getTotalRewardsDistributed(),
            currentFundingRound: funding.currentRoundId(),
            totalFundingAllocated: _getTotalFundingAllocated()
        });
    }

    /**
     * @notice Gets active funding round information
     * @param roundId Round ID to query
     * @param snapshotBlock Block number for XP snapshot
     * @param startTime Round start time
     * @param endTime Round end time
     * @param finalized Whether round is finalized
     * @param options Array of voting options
     */
    function getCurrentFundingRound()
        external
        view
        returns (
            uint256 roundId,
            uint256 snapshotBlock,
            uint64 startTime,
            uint64 endTime,
            bool finalized,
            bytes32[] memory options
        )
    {
        uint256 currentRound = funding.currentRoundId();
        if (currentRound > 0) {
            (snapshotBlock, startTime, endTime, finalized, options) =
                funding.getRound(currentRound - 1);
            roundId = currentRound - 1;
        } else {
            return (0, 0, 0, 0, false, new bytes32[](0));
        }
    }

    /**
     * @notice Gets user's voting status for a specific round
     * @param user User address
     * @param roundId Round ID
     * @return userXP XP available for voting
     * @return usedXP XP already used in voting
     * @return remainingXP XP still available
     */
    function getUserVotingStatus(address user, uint256 roundId)
        external
        view
        returns (uint256 userXP, uint256 usedXP, uint256 remainingXP)
    {
        (uint256 snapshotBlock,,,,) = funding.getRound(roundId);
        userXP = xp.getPastXP(user, snapshotBlock);
        // Note: usedXP would need to be tracked in LotPool - see enhancement below
        usedXP = 0; // Placeholder
        remainingXP = userXP - usedXP;
    }

    /**
     * @notice Batch query for multiple user balances
     * @param users Array of user addresses
     * @return Array of ELTA balances
     */
    function getBatchELTABalances(address[] calldata users)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory balances = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = elta.balanceOf(users[i]);
        }
        return balances;
    }

    /**
     * @notice Batch query for multiple user XP balances
     * @param users Array of user addresses
     * @return Array of XP balances
     */
    function getBatchXPBalances(address[] calldata users)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory balances = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = xp.balanceOf(users[i]);
        }
        return balances;
    }

    // Internal helper functions

    function _getPositionSummary(uint256 tokenId) internal view returns (PositionSummary memory) {
        // Not used (kept for interface compatibility, always returns empty)
        return PositionSummary({
            tokenId: tokenId,
            amount: 0,
            startTime: 0,
            endTime: 0,
            votingPower: 0,
            delegate: address(0),
            isExpired: true,
            emergencyUnlocked: false,
            timeRemaining: 0
        });
    }

    function _getTotalStaked(address user) internal view returns (uint256) {
        // Single lock per user - get principal from lock
        (uint256 principal,,,) = staking.getLockDetails(user);
        return principal;
    }

    function _calculateTotalValueLocked() internal view returns (uint256) {
        // This would require iterating through all positions
        // For gas efficiency, this could be tracked via events off-chain
        return elta.balanceOf(address(staking));
    }

    function _calculateAverageLockDuration() internal view returns (uint256) {
        // Placeholder - would require tracking lock durations
        return 52 weeks; // Default assumption
    }

    function _getTotalRewardsDistributed() internal view returns (uint256) {
        // Track via veEpochs sum (ELTA rewards only)
        uint256 epochCount = rewards.getEpochCount();
        uint256 totalDistributed = 0;

        for (uint256 i = 0; i < epochCount; i++) {
            (, uint256 amount) = rewards.getEpoch(i);
            totalDistributed += amount;
        }

        return totalDistributed;
    }

    function _getTotalFundingAllocated() internal view returns (uint256) {
        // This would need to be tracked via events or additional state
        return elta.balanceOf(address(funding));
    }
}
