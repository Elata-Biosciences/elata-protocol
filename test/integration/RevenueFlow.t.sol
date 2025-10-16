// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { AppFeeRouter } from "../../src/fees/AppFeeRouter.sol";
import { AppRewardsDistributor } from "../../src/rewards/AppRewardsDistributor.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import { IVeEltaVotes } from "../../src/interfaces/IVeEltaVotes.sol";
import { IRewardsDistributor } from "../../src/interfaces/IRewardsDistributor.sol";

/**
 * @title RevenueFlowTest
 * @notice Integration test for the full 70/15/15 revenue flow
 * @dev Tests the complete path:
 *      Trading Fee → AppFeeRouter → RewardsDistributor →
 *        70% AppRewardsDistributor → App Stakers
 *        15% veELTA epochs → veELTA stakers
 *        15% Treasury
 */
contract RevenueFlowTest is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppFeeRouter public feeRouter;
    AppRewardsDistributor public appRewardsDistributor;
    RewardsDistributor public rewardsDistributor;

    AppToken public appToken;
    AppStakingVault public appVault;

    address public governance = address(0x1);
    address public treasury = address(0x2);
    address public factory = address(0x3);
    address public bondingCurve = address(0x4);

    address public veStaker = address(0x10);
    address public appStaker = address(0x11);
    address public trader = address(0x12);

    uint256 constant BIPS_APP = 7000;
    uint256 constant BIPS_VEELTA = 1500;
    uint256 constant BIPS_TREASURY = 1500;

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA("ELTA", "ELTA", governance, governance, 10_000_000 ether, 0);

        // Deploy veELTA
        veElta = new VeELTA(elta, governance);

        // Deploy AppRewardsDistributor
        appRewardsDistributor = new AppRewardsDistributor(elta, governance, factory);

        // Deploy RewardsDistributor (casting interfaces for constructor)
        rewardsDistributor = new RewardsDistributor(
            elta,
            IVeEltaVotes(address(veElta)),
            IAppRewardsDistributor(address(appRewardsDistributor)),
            treasury,
            governance
        );

        // Deploy AppFeeRouter (casting interface for constructor)
        feeRouter =
            new AppFeeRouter(elta, IRewardsDistributor(address(rewardsDistributor)), governance);

        // Deploy app and vault
        appToken = new AppToken(
            "Game",
            "GAME",
            18,
            1_000_000 ether,
            governance,
            address(this),
            address(1),
            address(1),
            address(1),
            address(1)
        );
        appVault = new AppStakingVault("Game", "GAME", appToken, governance);
        appToken.mint(address(this), 1_000_000 ether);

        // Register app vault
        vm.prank(factory);
        appRewardsDistributor.registerApp(address(appVault));

        // Fund users
        vm.startPrank(governance);
        elta.transfer(veStaker, 10_000 ether);
        elta.transfer(trader, 100_000 ether);
        vm.stopPrank();

        appToken.transfer(appStaker, 10_000 ether);

        // Setup approvals
        vm.prank(veStaker);
        elta.approve(address(veElta), type(uint256).max);

        vm.prank(appStaker);
        appToken.approve(address(appVault), type(uint256).max);

        vm.prank(trader);
        elta.approve(address(feeRouter), type(uint256).max);

        vm.prank(bondingCurve);
        elta.approve(address(rewardsDistributor), type(uint256).max);
    }

    function test_FullRevenueFlow_70_15_15_Split() public {
        // 1) Setup: veELTA staker locks ELTA
        vm.prank(veStaker);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // 2) Setup: App staker stakes app tokens
        vm.prank(appStaker);
        appVault.stake(5000 ether);

        // Record initial balances
        uint256 treasuryBalanceBefore = elta.balanceOf(treasury);

        // 3) Simulate trading fee collection
        uint256 tradeAmount = 10_000 ether;
        uint256 tradingFee = (tradeAmount * feeRouter.feeBps()) / 10_000; // 1% = 100 ELTA

        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, tradeAmount);

        // 4) Verify split happened correctly
        uint256 expectedAppAmount = (tradingFee * BIPS_APP) / 10_000; // 70 ELTA
        uint256 expectedVeAmount = (tradingFee * BIPS_VEELTA) / 10_000; // 15 ELTA
        uint256 expectedTreasuryAmount = tradingFee - expectedAppAmount - expectedVeAmount; // 15 ELTA

        // Treasury should have received immediately
        assertEq(elta.balanceOf(treasury), treasuryBalanceBefore + expectedTreasuryAmount);

        // veELTA epoch should be recorded
        assertEq(rewardsDistributor.getEpochCount(), 1);
        (uint256 veBlockNumber, uint256 veAmount) = rewardsDistributor.getEpoch(0);
        assertEq(veBlockNumber, block.number);
        assertEq(veAmount, expectedVeAmount);

        // App epoch should be recorded
        assertEq(appRewardsDistributor.getEpochCount(address(appVault)), 1);
        (uint256 appBlockNumber, uint256 appAmount,) =
            appRewardsDistributor.epochs(address(appVault), 0);
        assertEq(appBlockNumber, block.number);
        assertEq(appAmount, expectedAppAmount);

        // 5) Roll forward for snapshot safety
        vm.roll(block.number + 1);

        // 6) veELTA staker claims
        uint256 veStakerBalanceBefore = elta.balanceOf(veStaker);

        vm.prank(veStaker);
        rewardsDistributor.claimVe(0, 1);

        assertEq(elta.balanceOf(veStaker), veStakerBalanceBefore + expectedVeAmount);

        // 7) App staker claims
        uint256 appStakerBalanceBefore = elta.balanceOf(appStaker);

        vm.prank(appStaker);
        appRewardsDistributor.claim(address(appVault), 1);

        assertEq(elta.balanceOf(appStaker), appStakerBalanceBefore + expectedAppAmount);
    }

    function test_MultipleApps_ProportionalDistribution() public {
        // Deploy second app
        AppToken appToken2 = new AppToken(
            "Game2",
            "GM2",
            18,
            1_000_000 ether,
            governance,
            address(this),
            address(1),
            address(1),
            address(1),
            address(1)
        );
        AppStakingVault appVault2 = new AppStakingVault("Game2", "GM2", appToken2, governance);
        appToken2.mint(address(this), 1_000_000 ether);

        vm.prank(factory);
        appRewardsDistributor.registerApp(address(appVault2));

        address appStaker2 = address(0x20);
        appToken2.transfer(appStaker2, 10_000 ether);
        vm.prank(appStaker2);
        appToken2.approve(address(appVault2), type(uint256).max);

        // App1: 3000 staked (75%), App2: 1000 staked (25%)
        vm.prank(appStaker);
        appVault.stake(3000 ether);

        vm.prank(appStaker2);
        appVault2.stake(1000 ether);

        // Generate revenue
        uint256 tradingFee = 100 ether;
        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, tradingFee * 100); // 1% fee

        uint256 expectedAppAmount = (tradingFee * BIPS_APP) / 10_000; // 70 ELTA

        vm.roll(block.number + 1);

        // Check distribution
        (, uint256 app1Amount,) = appRewardsDistributor.epochs(address(appVault), 0);
        (, uint256 app2Amount,) = appRewardsDistributor.epochs(address(appVault2), 0);

        assertApproxEqAbs(app1Amount, (expectedAppAmount * 75) / 100, 1); // 75% = 52.5 ELTA
        assertApproxEqAbs(app2Amount, (expectedAppAmount * 25) / 100, 1); // 25% = 17.5 ELTA

        // Both stakers claim
        vm.prank(appStaker);
        appRewardsDistributor.claim(address(appVault), 1);
        assertApproxEqAbs(elta.balanceOf(appStaker), app1Amount, 1);

        vm.prank(appStaker2);
        appRewardsDistributor.claim(address(appVault2), 1);
        assertApproxEqAbs(elta.balanceOf(appStaker2), app2Amount, 1);
    }

    function test_MultipleEpochs_AccumulatedRewards() public {
        // Setup stakers
        vm.prank(veStaker);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        vm.prank(appStaker);
        appVault.stake(5000 ether);

        // Generate multiple trading fees
        uint256[] memory fees = new uint256[](5);
        uint256 totalFees;

        for (uint256 i = 0; i < 5; i++) {
            fees[i] = (i + 1) * 10 ether; // 10, 20, 30, 40, 50 ELTA
            totalFees += fees[i];

            vm.prank(bondingCurve);
            feeRouter.takeAndForwardFee(trader, fees[i] * 100); // 1% fee

            vm.roll(block.number + 1);
        }

        // Calculate expected amounts
        uint256 expectedAppTotal = (totalFees * BIPS_APP) / 10_000;
        uint256 expectedVeTotal = (totalFees * BIPS_VEELTA) / 10_000;
        uint256 expectedTreasuryTotal = (totalFees * BIPS_TREASURY) / 10_000;

        // Verify treasury received immediately across all epochs
        assertApproxEqAbs(elta.balanceOf(treasury), expectedTreasuryTotal, 5);

        // veELTA staker claims all epochs
        vm.prank(veStaker);
        rewardsDistributor.claimVe(0, 5);
        // veStaker started with 10k, locked 1k, should get expectedVeTotal rewards
        assertApproxEqAbs(elta.balanceOf(veStaker), 10_000 ether - 1_000 ether + expectedVeTotal, 5);

        // App staker claims all epochs
        vm.prank(appStaker);
        appRewardsDistributor.claim(address(appVault), 5);
        assertApproxEqAbs(elta.balanceOf(appStaker), expectedAppTotal, 5);
    }

    function test_ZeroStake_NoRewards() public {
        // No one stakes

        // Generate revenue
        uint256 tradingFee = 100 ether;
        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, tradingFee * 100);

        vm.roll(block.number + 1);

        // veELTA epoch exists but no one can claim
        assertEq(rewardsDistributor.getEpochCount(), 1);
        uint256 estimated = rewardsDistributor.estimatePendingVeRewards(veStaker);
        assertEq(estimated, 0);

        // App epoch exists but with 0 allocation (no stakers)
        (, uint256 appAmount,) = appRewardsDistributor.epochs(address(appVault), 0);
        assertEq(appAmount, 0);
    }

    function test_StakeAfterDistribution_NoRewards() public {
        // Distribute first
        uint256 tradingFee = 100 ether;
        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, tradingFee * 100);

        vm.roll(block.number + 1);

        // Then stake
        vm.prank(veStaker);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        vm.prank(appStaker);
        appVault.stake(5000 ether);

        vm.roll(block.number + 1);

        // Should get nothing from past epoch
        vm.prank(veStaker);
        rewardsDistributor.claimVe(0, 1);
        assertEq(elta.balanceOf(veStaker), 10_000 ether - 1000 ether); // Only lost locked amount

        vm.prank(appStaker);
        appRewardsDistributor.claim(address(appVault), 1);
        assertEq(elta.balanceOf(appStaker), 0);
    }

    function test_PausedApp_NoRewards() public {
        // Setup stakers
        vm.prank(appStaker);
        appVault.stake(5000 ether);

        // Pause app
        vm.prank(governance);
        appRewardsDistributor.pauseApp(address(appVault), true);

        // Generate revenue
        uint256 tradingFee = 100 ether;
        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, tradingFee * 100);

        // App should get no epoch
        assertEq(appRewardsDistributor.getEpochCount(address(appVault)), 0);

        // But veELTA and treasury still get their shares
        uint256 expectedVe = (tradingFee * BIPS_VEELTA) / 10_000;
        uint256 expectedTreasury = (tradingFee * BIPS_TREASURY) / 10_000;

        assertEq(rewardsDistributor.getEpochCount(), 1);
        assertApproxEqAbs(elta.balanceOf(treasury), expectedTreasury, 1);
    }

    function test_InvariantCheck_TotalDistributedEqualsDeposited() public {
        // Setup stakers
        vm.prank(veStaker);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        vm.prank(appStaker);
        appVault.stake(5000 ether);

        // Generate multiple fees
        uint256 totalDeposited;

        for (uint256 i = 0; i < 10; i++) {
            uint256 fee = (i + 1) * 10 ether;
            totalDeposited += fee;

            vm.prank(bondingCurve);
            feeRouter.takeAndForwardFee(trader, fee * 100);
        }

        vm.roll(block.number + 1);

        // Calculate expected distribution
        uint256 expectedApp = (totalDeposited * BIPS_APP) / 10_000;
        uint256 expectedVe = (totalDeposited * BIPS_VEELTA) / 10_000;
        uint256 expectedTreasury = totalDeposited - expectedApp - expectedVe;

        // Treasury received immediately
        uint256 treasuryReceived = elta.balanceOf(treasury);

        // Claim all
        uint256 veBalanceBefore = elta.balanceOf(veStaker);
        vm.prank(veStaker);
        rewardsDistributor.claimVe(0, 10);
        uint256 veClaimed = elta.balanceOf(veStaker) - veBalanceBefore;

        uint256 appBalanceBefore = elta.balanceOf(appStaker);
        vm.prank(appStaker);
        appRewardsDistributor.claim(address(appVault), 10);
        uint256 appClaimed = elta.balanceOf(appStaker) - appBalanceBefore;

        // Total distributed should equal total deposited (within rounding)
        uint256 totalDistributed = treasuryReceived + veClaimed + appClaimed;
        assertApproxEqAbs(totalDistributed, totalDeposited, 10);

        // Individual shares should match expected (within rounding)
        assertApproxEqAbs(appClaimed, expectedApp, 5);
        assertApproxEqAbs(veClaimed, expectedVe, 5);
        assertApproxEqAbs(treasuryReceived, expectedTreasury, 5);
    }
}
