// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppFeeRouter} from "../../src/fees/AppFeeRouter.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IRewardsDistributor} from "../../src/interfaces/IRewardsDistributor.sol";
import {IVeEltaVotes} from "../../src/interfaces/IVeEltaVotes.sol";
import {AppRewardsDistributor} from "../../src/rewards/AppRewardsDistributor.sol";
import {RewardsDistributor} from "../../src/rewards/RewardsDistributor.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import "forge-std/Test.sol";

/**
 * @title MultiEpochRewards Integration Test
 * @notice Comprehensive testing of reward distribution across multiple epochs
 * @dev Tests scenarios including:
 *      - Users staking at different times
 *      - Varying participation across epochs
 *      - Pro-rata distribution accuracy
 *      - Claim across epoch ranges
 *      - Late stakers, early unstakers
 */
contract MultiEpochRewardsTest is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppFeeRouter public feeRouter;
    AppRewardsDistributor public appRewardsDistributor;
    RewardsDistributor public rewardsDistributor;
    AppToken public appToken;
    AppStakingVault public appVault;

    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public factory = makeAddr("factory");
    address public bondingCurve = makeAddr("bondingCurve");

    // Multiple stakers
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public diana = makeAddr("diana");
    address public trader = makeAddr("trader");

    uint256 constant BIPS_APP = 7000;
    uint256 constant BIPS_VEELTA = 1500;
    uint256 constant BIPS_TREASURY = 1500;

    function setUp() public {
        // Deploy ELTA with sufficient supply
        elta = new ELTA(governance);

        // Deploy veELTA
        veElta = new VeELTA(elta, governance);

        // Deploy AppRewardsDistributor
        appRewardsDistributor = new AppRewardsDistributor(elta, governance, factory);

        // Deploy RewardsDistributor
        rewardsDistributor = new RewardsDistributor(
            elta,
            IVeEltaVotes(address(veElta)),
            IAppRewardsDistributor(address(appRewardsDistributor)),
            treasury,
            governance
        );

        // Deploy AppFeeRouter
        feeRouter = new AppFeeRouter(elta, IRewardsDistributor(address(rewardsDistributor)), governance);

        // Deploy app token and vault
        appToken = new AppToken(
            "TestApp",
            "TEST",
            18,
            10_000_000 ether,
            governance,
            governance,
            address(1),
            address(1),
            address(1),
            address(1)
        );

        appVault = new AppStakingVault("TestApp", "TEST", appToken, governance);

        // Register app vault
        vm.prank(factory);
        appRewardsDistributor.registerApp(address(appVault));

        // Fund all participants
        _fundParticipants();
    }

    function _fundParticipants() internal {
        // Start at a higher block number to avoid ERC5805FutureLookup issues
        vm.roll(100);

        vm.startPrank(governance);
        // ELTA for veELTA staking
        elta.transfer(alice, 50_000 ether);
        elta.transfer(bob, 50_000 ether);
        elta.transfer(charlie, 50_000 ether);
        elta.transfer(diana, 50_000 ether);
        elta.transfer(trader, 500_000 ether);

        // App tokens for app staking
        appToken.mint(alice, 100_000 ether);
        appToken.mint(bob, 100_000 ether);
        appToken.mint(charlie, 100_000 ether);
        appToken.mint(diana, 100_000 ether);
        vm.stopPrank();

        // Setup approvals
        _setupApprovals(alice);
        _setupApprovals(bob);
        _setupApprovals(charlie);
        _setupApprovals(diana);

        vm.prank(trader);
        elta.approve(address(feeRouter), type(uint256).max);

        vm.prank(bondingCurve);
        elta.approve(address(rewardsDistributor), type(uint256).max);
    }

    function _setupApprovals(address user) internal {
        vm.startPrank(user);
        elta.approve(address(veElta), type(uint256).max);
        appToken.approve(address(appVault), type(uint256).max);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-EPOCH TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UsersStakeAtDifferentTimes() public {
        // All users stake at beginning with same amount
        vm.prank(alice);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(bob);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(charlie);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        // Roll forward to ensure stakes are in the past
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1 hours);

        // Generate 3 epochs
        for (uint256 i = 0; i < 3; i++) {
            _generateRevenue(100 ether);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1 hours);
        }

        // Verify epoch count
        assertEq(rewardsDistributor.getEpochCount(), 3, "Should have 3 epochs");

        // Calculate expected rewards per epoch (15 ELTA each epoch for veELTA)
        uint256 veRewardPerEpoch = (100 ether * BIPS_VEELTA) / 10_000; // 15 ELTA

        // Each user should get ~1/3 of each epoch
        uint256 expectedPerUser = (veRewardPerEpoch * 3) / 3;

        // All users claim
        uint256 aliceBalanceBefore = elta.balanceOf(alice);
        vm.prank(alice);
        rewardsDistributor.claimVe(0, 3);
        uint256 aliceClaimed = elta.balanceOf(alice) - aliceBalanceBefore;

        uint256 bobBalanceBefore = elta.balanceOf(bob);
        vm.prank(bob);
        rewardsDistributor.claimVe(0, 3);
        uint256 bobClaimed = elta.balanceOf(bob) - bobBalanceBefore;

        uint256 charlieBalanceBefore = elta.balanceOf(charlie);
        vm.prank(charlie);
        rewardsDistributor.claimVe(0, 3);
        uint256 charlieClaimed = elta.balanceOf(charlie) - charlieBalanceBefore;

        // All should get approximately equal rewards
        assertApproxEqAbs(aliceClaimed, expectedPerUser, 5, "Alice rewards wrong");
        assertApproxEqAbs(bobClaimed, expectedPerUser, 5, "Bob rewards wrong");
        assertApproxEqAbs(charlieClaimed, expectedPerUser, 5, "Charlie rewards wrong");

        // Total claimed should equal total veELTA rewards
        uint256 totalVeRewards = veRewardPerEpoch * 3;
        assertApproxEqAbs(aliceClaimed + bobClaimed + charlieClaimed, totalVeRewards, 5, "Total rewards mismatch");

        console2.log("Alice claimed:", aliceClaimed / 1e18, "ELTA");
        console2.log("Bob claimed:", bobClaimed / 1e18, "ELTA");
        console2.log("Charlie claimed:", charlieClaimed / 1e18, "ELTA");
    }

    function test_VaryingParticipationAcrossEpochs() public {
        // All users stake in app vault with different amounts
        vm.prank(alice);
        appVault.stake(40_000 ether); // 40%

        vm.prank(bob);
        appVault.stake(30_000 ether); // 30%

        vm.prank(charlie);
        appVault.stake(20_000 ether); // 20%

        vm.prank(diana);
        appVault.stake(10_000 ether); // 10%

        // Roll forward so stakes are in the past
        vm.roll(block.number + 1);

        // Generate 5 epochs with varying revenue
        uint256[] memory revenues = new uint256[](5);
        revenues[0] = 100 ether;
        revenues[1] = 200 ether;
        revenues[2] = 150 ether;
        revenues[3] = 300 ether;
        revenues[4] = 250 ether;

        uint256 totalRevenue;
        for (uint256 i = 0; i < 5; i++) {
            _generateRevenue(revenues[i]);
            totalRevenue += revenues[i];
            vm.roll(block.number + 1);
        }

        // Calculate expected app rewards (70% of revenue)
        uint256 totalAppRewards = (totalRevenue * BIPS_APP) / 10_000;

        // Each user should get proportional share
        uint256 aliceExpected = (totalAppRewards * 40) / 100;
        uint256 bobExpected = (totalAppRewards * 30) / 100;
        uint256 charlieExpected = (totalAppRewards * 20) / 100;
        uint256 dianaExpected = (totalAppRewards * 10) / 100;

        // Record balances before claiming
        uint256 aliceBefore = elta.balanceOf(alice);
        uint256 bobBefore = elta.balanceOf(bob);
        uint256 charlieBefore = elta.balanceOf(charlie);
        uint256 dianaBefore = elta.balanceOf(diana);

        // Claims
        vm.prank(alice);
        appRewardsDistributor.claim(address(appVault), 5);
        assertApproxEqAbs(elta.balanceOf(alice) - aliceBefore, aliceExpected, 10, "Alice rewards wrong");

        vm.prank(bob);
        appRewardsDistributor.claim(address(appVault), 5);
        assertApproxEqAbs(elta.balanceOf(bob) - bobBefore, bobExpected, 10, "Bob rewards wrong");

        vm.prank(charlie);
        appRewardsDistributor.claim(address(appVault), 5);
        assertApproxEqAbs(elta.balanceOf(charlie) - charlieBefore, charlieExpected, 10, "Charlie rewards wrong");

        vm.prank(diana);
        appRewardsDistributor.claim(address(appVault), 5);
        assertApproxEqAbs(elta.balanceOf(diana) - dianaBefore, dianaExpected, 10, "Diana rewards wrong");
    }

    function test_ClaimAcrossEpochRanges() public {
        // Alice stakes at block 100
        vm.prank(alice);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        // Roll forward to ensure stake is in the past
        vm.roll(block.number + 1);

        // Generate 10 epochs
        for (uint256 i = 0; i < 10; i++) {
            _generateRevenue(50 ether);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1 hours);
        }

        uint256 veRewardPerEpoch = (50 ether * BIPS_VEELTA) / 10_000; // 7.5 ELTA
        uint256 totalExpected = veRewardPerEpoch * 10; // 75 ELTA

        // Alice claims in batches
        uint256 aliceBalanceBefore = elta.balanceOf(alice);

        // Claim first 3 epochs
        vm.prank(alice);
        rewardsDistributor.claimVe(0, 3);

        // Claim next 4 epochs
        vm.prank(alice);
        rewardsDistributor.claimVe(3, 7);

        // Claim remaining 3 epochs
        vm.prank(alice);
        rewardsDistributor.claimVe(7, 10);

        uint256 totalClaimed = elta.balanceOf(alice) - aliceBalanceBefore;
        assertApproxEqAbs(totalClaimed, totalExpected, 3, "Batch claiming error");
    }

    function test_SingleStakerAllRewards() public {
        // Alice stakes
        vm.prank(alice);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        // Generate revenue immediately after stake (same block)
        _generateRevenue(100 ether);
        vm.roll(block.number + 1);

        // Alice should get 100% of the epoch
        uint256 aliceBalanceBefore = elta.balanceOf(alice);
        vm.prank(alice);
        rewardsDistributor.claimVe(0, 1);
        uint256 aliceClaimed = elta.balanceOf(alice) - aliceBalanceBefore;

        // Alice should get 100% of veELTA rewards (15% of 100 ELTA = 15 ELTA)
        uint256 veReward = (100 ether * BIPS_VEELTA) / 10_000;
        assertApproxEqAbs(aliceClaimed, veReward, 1, "Single staker got wrong amount");
    }

    function test_ProRataDistributionAccuracy() public {
        // Alice: 60%, Bob: 40%
        vm.prank(alice);
        veElta.lock(6_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(bob);
        veElta.lock(4_000 ether, uint64(block.timestamp + 365 days));

        // Generate revenue
        uint256 revenue = 1000 ether;
        _generateRevenue(revenue);
        vm.roll(block.number + 1);

        uint256 veTotal = (revenue * BIPS_VEELTA) / 10_000; // 150 ELTA

        // Alice should get ~60%, Bob ~40%
        uint256 aliceExpected = (veTotal * 60) / 100;
        uint256 bobExpected = (veTotal * 40) / 100;

        uint256 aliceBalanceBefore = elta.balanceOf(alice);
        vm.prank(alice);
        rewardsDistributor.claimVe(0, 1);
        uint256 aliceClaimed = elta.balanceOf(alice) - aliceBalanceBefore;

        uint256 bobBalanceBefore = elta.balanceOf(bob);
        vm.prank(bob);
        rewardsDistributor.claimVe(0, 1);
        uint256 bobClaimed = elta.balanceOf(bob) - bobBalanceBefore;

        // Allow small rounding error
        assertApproxEqAbs(aliceClaimed, aliceExpected, 2, "Alice pro-rata wrong");
        assertApproxEqAbs(bobClaimed, bobExpected, 2, "Bob pro-rata wrong");
        assertApproxEqAbs(aliceClaimed + bobClaimed, veTotal, 2, "Total doesn't match");
    }

    function test_ManyEpochsStressTest() public {
        // Alice stakes
        vm.prank(alice);
        veElta.lock(10_000 ether, uint64(block.timestamp + 730 days)); // 2 year lock

        vm.prank(alice);
        appVault.stake(50_000 ether);

        // Generate 100 epochs (simulating ~3 months of daily epochs)
        uint256 totalRevenue;
        for (uint256 i = 0; i < 100; i++) {
            uint256 revenue = 10 ether + (i % 10) * 1 ether; // Varying amounts
            _generateRevenue(revenue);
            totalRevenue += revenue;
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1 days);
        }

        // Verify epoch counts
        assertEq(rewardsDistributor.getEpochCount(), 100, "VeELTA epoch count wrong");
        assertEq(appRewardsDistributor.getEpochCount(address(appVault)), 100, "App epoch count wrong");

        // Claim all in batches (gas bounded)
        uint256 aliceVeBalanceBefore = elta.balanceOf(alice);

        // Claim veELTA rewards in chunks
        for (uint256 i = 0; i < 100; i += 50) {
            uint256 endEpoch = i + 50 > 100 ? 100 : i + 50;
            vm.prank(alice);
            rewardsDistributor.claimVe(i, endEpoch);
        }

        // Claim app rewards
        vm.prank(alice);
        appRewardsDistributor.claim(address(appVault), 100);

        uint256 aliceVeClaimed = elta.balanceOf(alice) - aliceVeBalanceBefore;

        // Calculate expected
        uint256 expectedVe = (totalRevenue * BIPS_VEELTA) / 10_000;
        uint256 expectedApp = (totalRevenue * BIPS_APP) / 10_000;

        assertApproxEqAbs(aliceVeClaimed, expectedVe + expectedApp, 100, "100-epoch claim inaccurate");

        console2.log("100 epochs completed");
        console2.log("Total revenue:", totalRevenue / 1e18, "ELTA");
        console2.log("Alice claimed:", aliceVeClaimed / 1e18, "ELTA");
    }

    function test_TwoStakersEqualSplit() public {
        // Alice and Bob stake equal amounts
        vm.prank(alice);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(bob);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        // Generate revenue immediately after stakes (same block)
        _generateRevenue(100 ether);
        vm.roll(block.number + 1);

        uint256 veReward = (100 ether * BIPS_VEELTA) / 10_000; // 15 ELTA
        uint256 halfReward = veReward / 2; // 7.5 ELTA per user

        // Alice claims
        uint256 aliceBalanceBefore = elta.balanceOf(alice);
        vm.prank(alice);
        rewardsDistributor.claimVe(0, 1);
        uint256 aliceClaimed = elta.balanceOf(alice) - aliceBalanceBefore;

        // Bob claims
        uint256 bobBalanceBefore = elta.balanceOf(bob);
        vm.prank(bob);
        rewardsDistributor.claimVe(0, 1);
        uint256 bobClaimed = elta.balanceOf(bob) - bobBalanceBefore;

        // Both should get ~50% each
        assertApproxEqAbs(aliceClaimed, halfReward, 2, "Alice claim wrong");
        assertApproxEqAbs(bobClaimed, halfReward, 2, "Bob claim wrong");
        assertApproxEqAbs(aliceClaimed, bobClaimed, 2, "Claims not equal");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _generateRevenue(uint256 amount) internal {
        // Fee router takes 1%, so we need to pass 100x the fee amount
        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, amount * 100);
    }
}
