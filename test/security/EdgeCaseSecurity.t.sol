// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { Errors } from "../../src/utils/Errors.sol";

/**
 * @title Edge Case Security Tests
 * @notice Tests for edge cases, boundary conditions, and potential exploits
 * @dev Tests extreme values, edge cases, and potential DoS attacks
 */
contract EdgeCaseSecurityTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataXP public xp;
    LotPool public funding;
    RewardsDistributor public rewards;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        xp = new ElataXP(admin);
        staking = new VeELTA(elta, admin);
        funding = new LotPool(elta, xp, admin);
        rewards = new RewardsDistributor(staking, admin);
        
        // Distribute tokens
        vm.startPrank(treasury);
        elta.transfer(user1, 1_000_000 ether);
        elta.transfer(user2, 500_000 ether);
        vm.stopPrank();
    }

    function test_Security_MaximumLockDuration() public {
        // Test behavior at maximum lock duration
        
        vm.startPrank(user1);
        elta.approve(address(staking), 1_000_000 ether);
        
        uint256 tokenId = staking.createLock(1_000_000 ether, staking.MAX_LOCK());
        
        // Voting power should equal locked amount for max lock
        uint256 votingPower = staking.getPositionVotingPower(tokenId);
        assertEq(votingPower, 1_000_000 ether);
        
        // Try to extend beyond maximum (should fail)
        vm.expectRevert(Errors.LockTooLong.selector);
        staking.increaseUnlockTime(tokenId, block.timestamp + staking.MAX_LOCK() + 1);
        
        vm.stopPrank();
    }

    function test_Security_MinimumLockDuration() public {
        // Test behavior at minimum lock duration
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        
        uint256 tokenId = staking.createLock(100_000 ether, staking.MIN_LOCK());
        
        // Voting power should be minimal for min lock
        uint256 votingPower = staking.getPositionVotingPower(tokenId);
        uint256 expectedPower = (100_000 ether * staking.MIN_LOCK()) / staking.MAX_LOCK();
        assertEq(votingPower, expectedPower);
        
        // Try to create lock shorter than minimum (should fail)
        vm.expectRevert(Errors.LockTooShort.selector);
        staking.createLock(100_000 ether, staking.MIN_LOCK() - 1);
        
        vm.stopPrank();
    }

    function test_Security_ZeroAmountProtection() public {
        // Test protection against zero amounts in all functions
        
        // Zero amount lock
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(user1);
        staking.createLock(0, 52 weeks);
        
        // Zero amount increase
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        
        vm.expectRevert(Errors.InvalidAmount.selector);
        staking.increaseAmount(tokenId, 0);
        vm.stopPrank();
        
        // Zero amount XP award
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        xp.award(user1, 0);
        
        // Zero amount XP revoke
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        xp.revoke(user1, 0);
        
        // Zero amount funding
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(treasury);
        funding.fund(0);
    }

    function test_Security_ArrayLengthMismatch() public {
        // Test protection against array length mismatches
        
        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("OPTION_1");
        options[1] = keccak256("OPTION_2");
        
        address[] memory recipients = new address[](1); // Mismatched length
        recipients[0] = user1;
        
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(admin);
        funding.startRound(options, recipients, 7 days);
    }

    function test_Security_DuplicateOptionPrevention() public {
        // Test prevention of duplicate options in funding rounds
        
        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("OPTION_1");
        options[1] = keccak256("OPTION_1"); // Duplicate
        
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        
        vm.expectRevert(Errors.DuplicateOption.selector);
        vm.prank(admin);
        funding.startRound(options, recipients, 7 days);
    }

    function test_Security_ExpiredLockOperations() public {
        // Test behavior with expired locks
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 53 weeks);
        
        // Voting power should be zero
        assertEq(staking.getPositionVotingPower(tokenId), 0);
        
        // Cannot increase expired position
        vm.expectRevert(Errors.LockNotExpired.selector);
        vm.prank(user1);
        staking.increaseAmount(tokenId, 10_000 ether);
        
        // Cannot extend expired position
        vm.expectRevert(Errors.LockNotExpired.selector);
        vm.prank(user1);
        staking.increaseUnlockTime(tokenId, block.timestamp + 26 weeks);
        
        // Can withdraw expired position
        vm.prank(user1);
        staking.withdraw(tokenId);
        
        // Position should be cleared
        (uint128 amount,,,, ) = staking.positions(tokenId);
        assertEq(amount, 0);
    }

    function test_Security_XPDecayEdgeCases() public {
        // Test XP decay at boundary conditions
        
        vm.prank(admin);
        xp.award(user1, 10_000 ether);
        
        // At exactly decay window, effective balance should be 0
        vm.warp(block.timestamp + xp.DECAY_WINDOW());
        assertEq(xp.effectiveBalance(user1), 0);
        
        // Beyond decay window, still 0
        vm.warp(block.timestamp + 1 days);
        assertEq(xp.effectiveBalance(user1), 0);
        
        // Award new XP after full decay
        vm.prank(admin);
        xp.award(user1, 5_000 ether);
        
        // New XP should be at full value
        assertEq(xp.effectiveBalance(user1), 5_000 ether);
        
        // Apply decay to remove old entries
        xp.updateUserDecay(user1);
        
        // Should only have new XP
        assertEq(xp.balanceOf(user1), 5_000 ether);
    }

    function test_Security_MaxPositionsPerUser() public {
        // Test creating many positions to check for DoS
        
        vm.startPrank(user1);
        elta.approve(address(staking), 1_000_000 ether);
        
        // Create multiple positions
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            tokenIds[i] = staking.createLock(50_000 ether, 52 weeks);
        }
        
        // Verify all positions were created
        assertEq(staking.balanceOf(user1), 10);
        
        // Getting user voting power should still work (no DoS)
        uint256 totalPower = staking.getUserVotingPower(user1);
        assertGt(totalPower, 0);
        
        // Getting positions should work
        uint256[] memory positions = staking.getUserPositions(user1);
        assertEq(positions.length, 10);
        
        vm.stopPrank();
    }

    function test_Security_RewardDistributionEdgeCases() public {
        // Test edge cases in reward distribution
        
        vm.prank(admin);
        rewards.addRewardToken(elta);
        
        // Try to deposit zero rewards
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        rewards.depositRewards(address(elta), 0);
        
        // Deposit small amount of rewards
        vm.startPrank(treasury);
        elta.approve(address(rewards), 1 ether);
        
        vm.stopPrank();
        vm.prank(admin);
        rewards.grantRole(rewards.DISTRIBUTOR_ROLE(), treasury);
        
        vm.prank(treasury);
        rewards.depositRewards(address(elta), 1 ether);
        
        // Finalize epoch
        vm.warp(block.timestamp + 8 days);
        vm.prank(treasury);
        rewards.finalizeEpoch(keccak256("small_reward_root"));
        
        // System should handle small rewards correctly
        (,,,, bool finalized) = rewards.getCurrentEpoch();
        assertTrue(finalized);
    }

    function test_Security_BatchOperationLimits() public {
        // Test batch operations for potential DoS
        
        // Create large array of users for batch decay
        address[] memory users = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            vm.prank(admin);
            xp.award(users[i], 1000 ether);
        }
        
        // Fast forward to trigger decay
        vm.warp(block.timestamp + 15 days);
        
        // Wait for decay interval
        vm.warp(block.timestamp + 2 hours);
        
        // Batch update should work even with many users
        vm.prank(admin);
        xp.batchUpdateDecay(users);
        
        // Verify decay was applied
        for (uint256 i = 0; i < 10; i++) { // Check first 10
            assertEq(xp.balanceOf(users[i]), 0);
        }
    }

    function test_Security_TimestampManipulation() public {
        // Test resilience against timestamp manipulation
        
        vm.prank(admin);
        xp.award(user1, 10_000 ether);
        
        uint256 awardTime = block.timestamp;
        
        // Simulate small timestamp manipulation (within block time variance)
        vm.warp(awardTime + 15); // 15 seconds later
        
        // Effective balance should be essentially unchanged
        uint256 effectiveBalance = xp.effectiveBalance(user1);
        assertApproxEqRel(effectiveBalance, 10_000 ether, 0.001e18); // 0.1% tolerance
        
        // Large timestamp jumps should be handled correctly
        vm.warp(awardTime + 7 days);
        uint256 weekLaterBalance = xp.effectiveBalance(user1);
        assertApproxEqRel(weekLaterBalance, 5_000 ether, 0.01e18); // ~50% after 7 days
    }

    function test_Security_PositionManipulationAttempts() public {
        // Test attempts to manipulate position data
        
        vm.startPrank(user1);
        elta.approve(address(staking), 200_000 ether);
        
        uint256 tokenId1 = staking.createLock(100_000 ether, 52 weeks);
        uint256 tokenId2 = staking.createLock(100_000 ether, 78 weeks);
        
        // Try to merge positions where user doesn't own one
        vm.stopPrank();
        
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(user2);
        staking.mergePositions(tokenId1, tokenId2);
        
        // Try to split position user doesn't own
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(user2);
        staking.splitPosition(tokenId1, 50_000 ether);
        
        // Original owner should still have control
        vm.prank(user1);
        staking.mergePositions(tokenId1, tokenId2);
        
        assertEq(staking.balanceOf(user1), 1); // One position after merge
    }

    function test_Security_VotingRoundManipulation() public {
        // Test attempts to manipulate voting rounds
        
        vm.prank(admin);
        xp.award(user1, 5000 ether);
        
        // Start round
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("TEST_OPTION");
        
        address[] memory recipients = new address[](1);
        recipients[0] = user1;
        
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        // Try to vote before round starts (manipulate timestamp)
        vm.warp(block.timestamp - 1);
        vm.expectRevert(Errors.VotingNotStarted.selector);
        vm.prank(user1);
        funding.vote(roundId, options[0], 1000 ether);
        
        // Reset timestamp and vote normally
        vm.warp(block.timestamp + 1);
        vm.prank(user1);
        funding.vote(roundId, options[0], 5000 ether);
        
        // Try to vote after round ends
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(Errors.VotingClosed.selector);
        vm.prank(user1);
        funding.vote(roundId, options[0], 1 ether);
    }

    function test_Security_RewardClaimingEdgeCases() public {
        // Test edge cases in reward claiming
        
        vm.prank(admin);
        rewards.addRewardToken(elta);
        
        // Setup epoch with minimal rewards
        vm.startPrank(treasury);
        elta.approve(address(rewards), 1 ether);
        vm.stopPrank();
        
        vm.prank(admin);
        rewards.grantRole(rewards.DISTRIBUTOR_ROLE(), treasury);
        
        vm.prank(treasury);
        rewards.depositRewards(address(elta), 1 ether);
        
        // Finalize epoch
        vm.warp(block.timestamp + 8 days);
        vm.prank(treasury);
        rewards.finalizeEpoch(keccak256("minimal_rewards"));
        
        // Try to claim from future epoch
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(RewardsDistributor.InvalidEpoch.selector);
        vm.prank(user1);
        rewards.claimRewards(999, 1000 ether, proof);
        
        // Try to claim from unfinalized epoch
        vm.expectRevert(RewardsDistributor.EpochNotFinalized.selector);
        vm.prank(user1);
        rewards.claimRewards(1, 1000 ether, proof); // Current epoch not finalized
    }

    function test_Security_IntegerBoundaries() public {
        // Test behavior at integer boundaries
        
        // Test with uint128 maximum for position amount
        uint256 maxAmount = type(uint128).max;
        
        // This should fail due to insufficient balance, not overflow
        vm.expectRevert();
        vm.prank(user1);
        staking.createLock(maxAmount, 52 weeks);
        
        // Test with maximum timestamp values
        uint256 maxDuration = staking.MAX_LOCK();
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, maxDuration);
        
        // Should work correctly
        (uint128 amount, uint64 start, uint64 end,, ) = staking.positions(tokenId);
        assertEq(amount, 100_000 ether);
        assertEq(end, start + maxDuration);
        
        vm.stopPrank();
    }

    function test_Security_GasLimitDoSProtection() public {
        // Test protection against gas limit DoS attacks
        
        // Create many XP entries for a user
        vm.startPrank(admin);
        for (uint256 i = 0; i < 50; i++) {
            xp.award(user1, 100 ether);
            vm.warp(block.timestamp + 1 hours); // Space out awards
        }
        vm.stopPrank();
        
        // Decay calculation should still work with many entries
        uint256 effectiveBalance = xp.effectiveBalance(user1);
        assertGt(effectiveBalance, 0);
        
        // Decay update should work
        vm.warp(block.timestamp + 15 days);
        xp.updateUserDecay(user1);
        
        // Should have cleaned up old entries
        assertLt(xp.getUserXPEntryCount(user1), 50);
    }

    function test_Security_RoundingErrorAccumulation() public {
        // Test for rounding error accumulation in calculations
        
        // Create many small positions
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        
        uint256[] memory tokenIds = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            tokenIds[i] = staking.createLock(1000 ether, 52 weeks);
        }
        
        // Calculate total voting power
        uint256 totalPower = staking.getUserVotingPower(user1);
        
        // Should be close to expected value (100 * individual power)
        uint256 expectedIndividualPower = (1000 ether * 52 weeks) / staking.MAX_LOCK();
        uint256 expectedTotalPower = expectedIndividualPower * 100;
        
        assertApproxEqRel(totalPower, expectedTotalPower, 0.01e18);
        
        vm.stopPrank();
    }

    function testFuzz_Security_PositionSplitEdgeCases(
        uint256 totalAmount,
        uint256 splitAmount
    ) public {
        // Bound inputs to valid ranges
        totalAmount = bound(totalAmount, 2 ether, 100_000 ether);
        splitAmount = bound(splitAmount, 1 ether, totalAmount - 1 ether);
        
        vm.prank(treasury);
        elta.transfer(user1, totalAmount);
        
        vm.startPrank(user1);
        elta.approve(address(staking), totalAmount);
        uint256 tokenId = staking.createLock(totalAmount, 52 weeks);
        
        // Split should work within bounds
        uint256 newTokenId = staking.splitPosition(tokenId, splitAmount);
        
        // Verify split worked correctly
        (uint128 originalAmount,,,, ) = staking.positions(tokenId);
        (uint128 newAmount,,,, ) = staking.positions(newTokenId);
        
        assertEq(originalAmount, totalAmount - splitAmount);
        assertEq(newAmount, splitAmount);
        assertEq(staking.balanceOf(user1), 2);
        
        vm.stopPrank();
    }

    function testFuzz_Security_VotingWeightLimits(
        uint256 xpAmount,
        uint256 voteWeight
    ) public {
        // Test voting weight limits and edge cases
        xpAmount = bound(xpAmount, 1 ether, 1_000_000 ether);
        voteWeight = bound(voteWeight, 0, xpAmount * 2); // Include invalid weights
        
        vm.prank(admin);
        xp.award(user1, xpAmount);
        
        // Start round
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("FUZZ_OPTION");
        
        address[] memory recipients = new address[](1);
        recipients[0] = user1;
        
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        if (voteWeight == 0 || voteWeight > xpAmount) {
            // Should fail for zero weight or exceeding XP
            vm.expectRevert(Errors.InsufficientXP.selector);
            vm.prank(user1);
            funding.vote(roundId, options[0], voteWeight);
        } else {
            // Should succeed for valid weight
            vm.prank(user1);
            funding.vote(roundId, options[0], voteWeight);
            
            assertEq(funding.votesFor(roundId, options[0]), voteWeight);
        }
    }
}
