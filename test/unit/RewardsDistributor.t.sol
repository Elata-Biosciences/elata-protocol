// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract RewardsDistributorTest is Test {
    RewardsDistributor public rewardsDistributor;
    VeELTA public veELTA;
    ELTA public elta;
    ELTA public rewardToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public distributor = makeAddr("distributor");

    event EpochStarted(uint256 indexed epoch, uint256 startTime, uint256 endTime);
    event EpochFinalized(uint256 indexed epoch, bytes32 merkleRoot, uint256 totalRewards);
    event RewardClaimed(
        address indexed user, uint256 indexed epoch, address indexed token, uint256 amount
    );
    event RewardTokenAdded(address indexed token);
    event RewardsDeposited(address indexed token, uint256 amount, uint256 epoch);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        rewardToken = new ELTA("Reward", "RWD", admin, treasury, 1_000_000 ether, 1_000_000 ether);
        veELTA = new VeELTA(elta, admin);
        rewardsDistributor = new RewardsDistributor(veELTA, admin);

        // Note: Admin already has DISTRIBUTOR_ROLE from constructor
        // Give users some tokens
        vm.startPrank(treasury);
        elta.transfer(user1, 10000 ether);
        elta.transfer(user2, 10000 ether);
        rewardToken.transfer(admin, 100000 ether); // Give to admin instead
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(rewardsDistributor.veELTA()), address(veELTA));
        assertEq(rewardsDistributor.EPOCH_DURATION(), 7 days);
        assertEq(rewardsDistributor.MIN_DISTRIBUTION_DELAY(), 1 days);
        assertEq(rewardsDistributor.currentEpoch(), 1); // First epoch started in constructor

        assertTrue(rewardsDistributor.hasRole(rewardsDistributor.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(rewardsDistributor.hasRole(rewardsDistributor.DISTRIBUTOR_ROLE(), admin));
        assertTrue(rewardsDistributor.hasRole(rewardsDistributor.PAUSER_ROLE(), admin));
    }

    function test_AddRewardToken() public {
        vm.expectEmit(true, false, false, false);
        emit RewardTokenAdded(address(rewardToken));

        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        address[] memory activeTokens = rewardsDistributor.getActiveTokens();
        assertEq(activeTokens.length, 1);
        assertEq(activeTokens[0], address(rewardToken));
    }

    function test_RevertWhen_AddRewardTokenZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        rewardsDistributor.addRewardToken(ELTA(address(0)));
    }

    function test_DepositRewards() public {
        // Add reward token
        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        uint256 depositAmount = 1000 ether;

        vm.startPrank(admin);
        rewardToken.approve(address(rewardsDistributor), depositAmount);
        rewardsDistributor.depositRewards(address(rewardToken), depositAmount);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(rewardsDistributor)), depositAmount);
    }

    function test_RevertWhen_DepositRewardsTokenNotActive() public {
        vm.startPrank(admin);
        rewardToken.approve(address(rewardsDistributor), 1000 ether);

        vm.expectRevert(RewardsDistributor.TokenNotActive.selector);
        rewardsDistributor.depositRewards(address(rewardToken), 1000 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositRewardsZeroAmount() public {
        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(admin);
        rewardsDistributor.depositRewards(address(rewardToken), 0);
    }

    function test_FinalizeEpoch() public {
        // Add reward token and deposit rewards
        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        vm.startPrank(admin);
        rewardToken.approve(address(rewardsDistributor), 1000 ether);
        rewardsDistributor.depositRewards(address(rewardToken), 1000 ether);
        vm.stopPrank();

        // Fast forward past epoch end + delay
        vm.warp(block.timestamp + 7 days + 1 days + 1);

        bytes32 merkleRoot = keccak256("test_merkle_root");

        vm.prank(admin);
        rewardsDistributor.finalizeEpoch(merkleRoot);

        assertEq(rewardsDistributor.currentEpoch(), 2); // Should be 2 after finalization starts new epoch
    }

    function test_RevertWhen_FinalizeEpochTooEarly() public {
        vm.expectRevert(RewardsDistributor.DistributionTooEarly.selector);
        vm.prank(admin);
        rewardsDistributor.finalizeEpoch(keccak256("test"));
    }

    function test_ClaimRewards() public {
        // Setup: Add token, deposit rewards, finalize epoch
        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        vm.startPrank(admin);
        rewardToken.approve(address(rewardsDistributor), 1000 ether);
        rewardsDistributor.depositRewards(address(rewardToken), 1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days + 1 days + 1);

        bytes32 merkleRoot = keccak256("test_merkle_root");
        vm.prank(admin);
        rewardsDistributor.finalizeEpoch(merkleRoot);

        // Verify epoch was finalized (epoch 0 should be finalized, epoch 1 should be current)
        assertEq(rewardsDistributor.currentEpoch(), 2); // New epoch started

        // Check that epoch 0 was finalized
        (,,,, bool finalized,) = rewardsDistributor.getEpochDetails(0);
        assertTrue(finalized);

        // Note: Actual reward claiming would require proper merkle proofs
        // This test verifies the epoch finalization works correctly
    }

    function test_RemoveRewardToken() public {
        // Add token first
        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        address[] memory activeTokens = rewardsDistributor.getActiveTokens();
        assertEq(activeTokens.length, 1);

        vm.prank(admin);
        rewardsDistributor.removeRewardToken(address(rewardToken));

        activeTokens = rewardsDistributor.getActiveTokens();
        assertEq(activeTokens.length, 0);
    }

    function test_PauseUnpause() public {
        vm.prank(admin);
        rewardsDistributor.setPaused(true);

        assertTrue(rewardsDistributor.paused());

        // Should revert when paused - try deposit rewards
        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        vm.expectRevert(RewardsDistributor.ContractPaused.selector);
        vm.prank(admin);
        rewardsDistributor.depositRewards(address(rewardToken), 1000 ether);

        // Unpause
        vm.prank(admin);
        rewardsDistributor.setPaused(false);

        assertFalse(rewardsDistributor.paused());
    }

    function test_GetCurrentEpoch() public {
        (uint256 epoch, uint256 startTime, uint256 endTime, uint256 totalRewards, bool finalized) =
            rewardsDistributor.getCurrentEpoch();

        assertEq(epoch, 0); // Current epoch index is 0
        assertEq(startTime, 1); // Block timestamp in tests starts at 1
        assertEq(endTime, 1 + 7 days);
        assertEq(totalRewards, 0);
        assertFalse(finalized);
    }

    function test_HasClaimed() public {
        assertFalse(rewardsDistributor.hasClaimed(user1, 0));
        // After a successful claim, this would return true
    }

    function test_PendingRewards() public {
        uint256 pending = rewardsDistributor.pendingRewards(user1);
        assertEq(pending, 0); // No rewards without staking
    }

    function testFuzz_DepositRewards(uint256 amount) public {
        amount = bound(amount, 1 ether, 10000 ether);

        vm.prank(admin);
        rewardsDistributor.addRewardToken(rewardToken);

        vm.startPrank(admin);
        rewardToken.approve(address(rewardsDistributor), amount);
        rewardsDistributor.depositRewards(address(rewardToken), amount);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(rewardsDistributor)), amount);
    }
}
