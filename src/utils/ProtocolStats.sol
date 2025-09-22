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
        uint256 xpEffectiveBalance;
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

    struct XPDecayInfo {
        uint256 currentBalance;
        uint256 effectiveBalance;
        uint256 decayRate;
        uint256 nextDecayAmount;
        uint256 timeToFullDecay;
        XPEntry[] entries;
    }

    struct XPEntry {
        uint256 amount;
        uint256 timestamp;
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
            xpEffectiveBalance: xp.effectiveBalance(user),
            stakingPositions: staking.balanceOf(user),
            totalStaked: _getTotalStaked(user),
            totalVotingPower: staking.getUserVotingPower(user),
            pendingRewards: rewards.pendingRewards(user),
            totalClaimedRewards: rewards.totalClaimed(user)
        });
    }

    /**
     * @notice Gets detailed information about all user positions
     * @param user User address
     * @return Array of position summaries
     */
    function getUserPositions(address user) external view returns (PositionSummary[] memory) {
        uint256[] memory tokenIds = staking.getUserPositions(user);
        PositionSummary[] memory positions = new PositionSummary[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            positions[i] = _getPositionSummary(tokenIds[i]);
        }

        return positions;
    }

    /**
     * @notice Gets XP decay information for a user
     * @param user User address
     * @return Detailed decay information
     */
    function getXPDecayInfo(address user) external view returns (XPDecayInfo memory) {
        uint256 currentBalance = xp.balanceOf(user);
        uint256 effectiveBalance = xp.effectiveBalance(user);
        
        ElataXP.XPEntry[] memory entries = xp.getUserXPEntries(user);
        XPEntry[] memory formattedEntries = new XPEntry[](entries.length);
        
        for (uint256 i = 0; i < entries.length; i++) {
            formattedEntries[i] = XPEntry({
                amount: entries[i].amount,
                timestamp: entries[i].timestamp
            });
        }

        return XPDecayInfo({
            currentBalance: currentBalance,
            effectiveBalance: effectiveBalance,
            decayRate: currentBalance > 0 ? ((currentBalance - effectiveBalance) * 10000) / currentBalance : 0,
            nextDecayAmount: currentBalance - effectiveBalance,
            timeToFullDecay: _calculateTimeToFullDecay(user),
            entries: formattedEntries
        });
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
    function getCurrentFundingRound() external view returns (
        uint256 roundId,
        uint256 snapshotBlock,
        uint64 startTime,
        uint64 endTime,
        bool finalized,
        bytes32[] memory options
    ) {
        uint256 currentRound = funding.currentRoundId();
        if (currentRound > 0) {
            (snapshotBlock, startTime, endTime, finalized, options) = funding.getRound(currentRound - 1);
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
    function getUserVotingStatus(address user, uint256 roundId) external view returns (
        uint256 userXP,
        uint256 usedXP,
        uint256 remainingXP
    ) {
        (uint256 snapshotBlock,,,, ) = funding.getRound(roundId);
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
    function getBatchELTABalances(address[] calldata users) external view returns (uint256[] memory) {
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
    function getBatchXPBalances(address[] calldata users) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            balances[i] = xp.balanceOf(users[i]);
        }
        return balances;
    }

    // Internal helper functions

    function _getPositionSummary(uint256 tokenId) internal view returns (PositionSummary memory) {
        (uint128 amount, uint64 start, uint64 end, address delegate, bool emergencyUnlocked) = 
            staking.positions(tokenId);

        bool isExpired = block.timestamp >= end;
        uint256 timeRemaining = isExpired ? 0 : end - block.timestamp;

        return PositionSummary({
            tokenId: tokenId,
            amount: amount,
            startTime: start,
            endTime: end,
            votingPower: staking.getPositionVotingPower(tokenId),
            delegate: delegate,
            isExpired: isExpired,
            emergencyUnlocked: emergencyUnlocked,
            timeRemaining: timeRemaining
        });
    }

    function _getTotalStaked(address user) internal view returns (uint256) {
        uint256[] memory tokenIds = staking.getUserPositions(user);
        uint256 totalStaked = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint128 amount,,,, ) = staking.positions(tokenIds[i]);
            totalStaked += amount;
        }

        return totalStaked;
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
        // Sum across all reward tokens
        address[] memory tokens = rewards.getActiveTokens();
        uint256 totalDistributed = 0;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            (,uint256 distributed,) = rewards.rewardTokens(tokens[i]);
            totalDistributed += distributed;
        }
        
        return totalDistributed;
    }

    function _getTotalFundingAllocated() internal view returns (uint256) {
        // This would need to be tracked via events or additional state
        return elta.balanceOf(address(funding));
    }

    function _calculateTimeToFullDecay(address user) internal view returns (uint256) {
        ElataXP.XPEntry[] memory entries = xp.getUserXPEntries(user);
        if (entries.length == 0) return 0;

        uint256 oldestTimestamp = type(uint256).max;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].timestamp < oldestTimestamp) {
                oldestTimestamp = entries[i].timestamp;
            }
        }

        uint256 ageOfOldest = block.timestamp - oldestTimestamp;
        if (ageOfOldest >= xp.DECAY_WINDOW()) return 0;
        
        return xp.DECAY_WINDOW() - ageOfOldest;
    }
}
