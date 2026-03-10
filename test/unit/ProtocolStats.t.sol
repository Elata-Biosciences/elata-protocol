// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IVeEltaVotes} from "../../src/interfaces/IVeEltaVotes.sol";
import {AppRewardsDistributor} from "../../src/rewards/AppRewardsDistributor.sol";
import {ElataPoints} from "../../src/experience/ElataPoints.sol";
import {ProtocolStats} from "../../src/utils/ProtocolStats.sol";
import {RewardsDistributor} from "../../src/rewards/RewardsDistributor.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ELTA} from "elta/ELTA.sol";
import "forge-std/Test.sol";

/**
 * @title ProtocolStats Unit Tests
 * @notice Comprehensive tests for the ProtocolStats view contract
 * @dev Tests all view functions and edge cases
 */
contract ProtocolStatsTest is Test {
    ProtocolStats public stats;
    ELTA public elta;
    VeELTA public veElta;
    ElataPoints public xp;
    RewardsDistributor public rewards;
    AppRewardsDistributor public appRewardsDistributor;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public factory = makeAddr("factory");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(treasury);

        // Deploy veELTA
        veElta = new VeELTA(elta, admin);

        // Deploy ElataPoints
        xp = new ElataPoints(admin);

        // Deploy AppRewardsDistributor
        appRewardsDistributor = new AppRewardsDistributor(elta, admin, factory);

        // Deploy RewardsDistributor
        rewards = new RewardsDistributor(
            elta, IVeEltaVotes(address(veElta)), IAppRewardsDistributor(address(appRewardsDistributor)), treasury, admin
        );

        // Deploy ProtocolStats
        stats = new ProtocolStats(elta, veElta, xp, rewards);

        vm.stopPrank();

        // Fund users
        vm.startPrank(treasury);
        elta.transfer(user1, 100_000 ether);
        elta.transfer(user2, 100_000 ether);
        elta.transfer(user3, 50_000 ether);
        vm.stopPrank();

        // Approvals
        vm.prank(user1);
        elta.approve(address(veElta), type(uint256).max);
        vm.prank(user2);
        elta.approve(address(veElta), type(uint256).max);
        vm.prank(user3);
        elta.approve(address(veElta), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public view {
        assertEq(address(stats.elta()), address(elta));
        assertEq(address(stats.staking()), address(veElta));
        assertEq(address(stats.xp()), address(xp));
        assertEq(address(stats.rewards()), address(rewards));
    }

    // ────────────────────────────────────────────────────────────────────────────
    // getUserSummary TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetUserSummary_NoPositions() public view {
        ProtocolStats.UserSummary memory summary = stats.getUserSummary(user1);

        // User has ELTA but no staking positions
        assertEq(summary.eltaBalance, 100_000 ether);
        assertEq(summary.veEltaVotingPower, 0); // No staking position, no voting power
        assertEq(summary.xpBalance, 0);
        assertEq(summary.stakingPositions, 0);
        assertEq(summary.totalStaked, 0);
        assertEq(summary.totalVotingPower, 0);
        assertEq(summary.pendingRewards, 0);
        assertEq(summary.totalClaimedRewards, 0);
    }

    function test_GetUserSummary_WithStaking() public {
        // User locks ELTA
        uint256 lockAmount = 10_000 ether;
        uint64 unlockTime = uint64(block.timestamp + 365 days);

        vm.prank(user1);
        veElta.lock(lockAmount, unlockTime);

        ProtocolStats.UserSummary memory summary = stats.getUserSummary(user1);

        assertEq(summary.eltaBalance, 90_000 ether); // 100k - 10k locked
        // stakingPositions returns veELTA balance (the voting power), not count
        assertGt(summary.stakingPositions, 0);
        assertEq(summary.totalStaked, lockAmount);
        assertGt(summary.totalVotingPower, 0); // Should have veELTA
    }

    function test_GetUserSummary_WithXP() public {
        // Award XP to user
        vm.prank(admin);
        xp.award(user1, 5000 ether);

        ProtocolStats.UserSummary memory summary = stats.getUserSummary(user1);

        assertEq(summary.xpBalance, 5000 ether);
    }

    function test_GetUserSummary_ZeroAddress() public view {
        ProtocolStats.UserSummary memory summary = stats.getUserSummary(address(0));

        assertEq(summary.eltaBalance, 0);
        assertEq(summary.xpBalance, 0);
        assertEq(summary.stakingPositions, 0);
        assertEq(summary.totalStaked, 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // getUserPositions TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetUserPositions_NoPosition() public view {
        ProtocolStats.PositionSummary[] memory positions = stats.getUserPositions(user1);

        assertEq(positions.length, 0);
    }

    function test_GetUserPositions_WithPosition() public {
        uint256 lockAmount = 10_000 ether;
        uint64 unlockTime = uint64(block.timestamp + 365 days);

        vm.prank(user1);
        veElta.lock(lockAmount, unlockTime);

        ProtocolStats.PositionSummary[] memory positions = stats.getUserPositions(user1);

        assertEq(positions.length, 1);
        assertEq(positions[0].amount, lockAmount);
        assertEq(positions[0].endTime, unlockTime);
        assertGt(positions[0].votingPower, 0);
        assertEq(positions[0].isExpired, false);
        assertGt(positions[0].timeRemaining, 0);
    }

    function test_GetUserPositions_ExpiredPosition() public {
        uint256 lockAmount = 10_000 ether;
        uint64 unlockTime = uint64(block.timestamp + 8 days); // MIN_LOCK + 1

        vm.prank(user1);
        veElta.lock(lockAmount, unlockTime);

        // Warp past unlock time
        vm.warp(unlockTime + 1);

        ProtocolStats.PositionSummary[] memory positions = stats.getUserPositions(user1);

        assertEq(positions.length, 1);
        assertEq(positions[0].isExpired, true);
        assertEq(positions[0].timeRemaining, 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // getProtocolSummary TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetProtocolSummary_Empty() public view {
        ProtocolStats.ProtocolSummary memory summary = stats.getProtocolSummary();

        assertEq(summary.totalValueLocked, 0);
        assertEq(summary.totalXPIssued, 0);
        assertEq(summary.totalActivePositions, 0);
        // averageLockDuration returns default 52 weeks
        assertEq(summary.averageLockDuration, 52 weeks);
        assertEq(summary.totalRewardsDistributed, 0);
    }

    function test_GetProtocolSummary_WithTVL() public {
        // Multiple users lock ELTA
        uint256 lockAmount1 = 10_000 ether;
        uint256 lockAmount2 = 20_000 ether;
        uint64 unlockTime = uint64(block.timestamp + 365 days);

        vm.prank(user1);
        veElta.lock(lockAmount1, unlockTime);

        vm.prank(user2);
        veElta.lock(lockAmount2, unlockTime);

        ProtocolStats.ProtocolSummary memory summary = stats.getProtocolSummary();

        assertEq(summary.totalValueLocked, lockAmount1 + lockAmount2);
        assertGt(summary.totalActivePositions, 0);
    }

    function test_GetProtocolSummary_WithXP() public {
        vm.prank(admin);
        xp.award(user1, 5000 ether);

        vm.prank(admin);
        xp.award(user2, 3000 ether);

        ProtocolStats.ProtocolSummary memory summary = stats.getProtocolSummary();

        assertEq(summary.totalXPIssued, 8000 ether);
    }

    function test_GetProtocolSummary_WithRewardsDistributed() public {
        // Create a revenueSource that can deposit
        address revenueSource = makeAddr("revenueSource");

        // Get role first (static call consumes prank)
        bytes32 distributorRole = rewards.DISTRIBUTOR_ROLE();

        // Grant DISTRIBUTOR_ROLE to revenueSource
        vm.prank(admin);
        rewards.grantRole(distributorRole, revenueSource);

        // Fund revenueSource
        vm.prank(treasury);
        elta.transfer(revenueSource, 10_000 ether);

        // Approve and deposit
        vm.startPrank(revenueSource);
        elta.approve(address(rewards), 10_000 ether);
        rewards.deposit(10_000 ether);
        vm.stopPrank();

        ProtocolStats.ProtocolSummary memory summary = stats.getProtocolSummary();

        // 15% of 10,000 = 1,500 goes to veELTA epochs
        assertEq(summary.totalRewardsDistributed, 1500 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // getBatchELTABalances TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetBatchELTABalances() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory balances = stats.getBatchELTABalances(users);

        assertEq(balances.length, 3);
        assertEq(balances[0], 100_000 ether);
        assertEq(balances[1], 100_000 ether);
        assertEq(balances[2], 50_000 ether);
    }

    function test_GetBatchELTABalances_Empty() public view {
        address[] memory users = new address[](0);

        uint256[] memory balances = stats.getBatchELTABalances(users);

        assertEq(balances.length, 0);
    }

    function test_GetBatchELTABalances_IncludesZeroAddresses() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = address(0);
        users[2] = user3;

        uint256[] memory balances = stats.getBatchELTABalances(users);

        assertEq(balances.length, 3);
        assertEq(balances[0], 100_000 ether);
        assertEq(balances[1], 0); // address(0) balance
        assertEq(balances[2], 50_000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // getBatchXPBalances TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetBatchXPBalances() public {
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        xp.award(user2, 2000 ether);
        xp.award(user3, 500 ether);
        vm.stopPrank();

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory balances = stats.getBatchXPBalances(users);

        assertEq(balances.length, 3);
        assertEq(balances[0], 1000 ether);
        assertEq(balances[1], 2000 ether);
        assertEq(balances[2], 500 ether);
    }

    function test_GetBatchXPBalances_Empty() public view {
        address[] memory users = new address[](0);

        uint256[] memory balances = stats.getBatchXPBalances(users);

        assertEq(balances.length, 0);
    }

    function test_GetBatchXPBalances_NoXP() public view {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory balances = stats.getBatchXPBalances(users);

        assertEq(balances.length, 2);
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_GetBatchELTABalances(uint8 numUsers) public {
        vm.assume(numUsers <= 50); // Reasonable limit

        address[] memory users = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        uint256[] memory balances = stats.getBatchELTABalances(users);

        assertEq(balances.length, numUsers);
    }

    function testFuzz_GetBatchXPBalances(uint8 numUsers) public {
        vm.assume(numUsers <= 50);

        address[] memory users = new address[](numUsers);
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        uint256[] memory balances = stats.getBatchXPBalances(users);

        assertEq(balances.length, numUsers);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASES
    // ────────────────────────────────────────────────────────────────────────────

    function test_GetUserSummary_WithStakingAndXP() public {
        // Test comprehensive user summary with both staking and XP

        // Setup staking
        uint256 lockAmount = 10_000 ether;
        uint64 unlockTime = uint64(block.timestamp + 365 days);

        vm.prank(user1);
        veElta.lock(lockAmount, unlockTime);

        // Award XP
        vm.prank(admin);
        xp.award(user1, 5000 ether);

        // Check summary shows all user data
        ProtocolStats.UserSummary memory summary = stats.getUserSummary(user1);

        // ELTA balance should decrease by locked amount
        assertEq(summary.eltaBalance, 90_000 ether); // 100k - 10k locked

        // XP balance
        assertEq(summary.xpBalance, 5000 ether);

        // Staking data
        assertEq(summary.totalStaked, lockAmount);
        assertGt(summary.totalVotingPower, 0);

        // Pending rewards should be 0 (no epochs created)
        assertEq(summary.pendingRewards, 0);
    }

    function test_GetProtocolSummary_RewardsFromMultipleEpochs() public {
        // Create a revenueSource that can deposit
        address revenueSource = makeAddr("revenueSource");

        // Get role first (static call consumes prank)
        bytes32 distributorRole = rewards.DISTRIBUTOR_ROLE();

        // Grant DISTRIBUTOR_ROLE to revenueSource
        vm.prank(admin);
        rewards.grantRole(distributorRole, revenueSource);

        // Fund revenueSource
        vm.prank(treasury);
        elta.transfer(revenueSource, 30_000 ether);

        // Approve and deposit multiple times
        vm.startPrank(revenueSource);
        elta.approve(address(rewards), 30_000 ether);
        rewards.deposit(10_000 ether);
        vm.roll(block.number + 1);
        rewards.deposit(10_000 ether);
        vm.roll(block.number + 1);
        rewards.deposit(10_000 ether);
        vm.stopPrank();

        ProtocolStats.ProtocolSummary memory summary = stats.getProtocolSummary();

        // Total rewards = 15% * 30,000 = 4,500
        assertEq(summary.totalRewardsDistributed, 4500 ether);
    }
}
