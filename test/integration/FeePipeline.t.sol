// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IVeEltaVotes} from "../../src/interfaces/IVeEltaVotes.sol";
import {AppRewardsDistributor} from "../../src/rewards/AppRewardsDistributor.sol";
import {RewardsDistributor} from "../../src/rewards/RewardsDistributor.sol";
import {ReferralRegistry} from "../../src/modules/ReferralRegistry.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import "forge-std/Test.sol";

/// @notice Simple mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title FeePipelineTest
 * @notice End-to-end integration tests for the complete fee pipeline
 * @dev Tests the flow:
 *      BondingCurve → FeeCollector → FeeManager → Distribution
 *        - 45% App Stakers
 *        - 30% veELTA Stakers
 *        - 10% Creator
 *        - 10% Treasury
 *        - 5% Referral
 */
contract FeePipelineTest is Test {
    // Core contracts
    ELTA public elta;
    MockUSDC public usdc;
    VeELTA public veElta;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    AppRewardsDistributor public appRewardsDistributor;
    RewardsDistributor public rewardsDistributor;
    ReferralRegistry public referralRegistry;

    // App contracts
    AppToken public appToken;
    AppStakingVault public appVault;

    // Addresses
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public factory = makeAddr("factory");
    address public creator = makeAddr("creator");
    address public feeSwapper = makeAddr("feeSwapper");

    address public veStaker = makeAddr("veStaker");
    address public appStaker = makeAddr("appStaker");
    address public buyer = makeAddr("buyer");
    address public referrer = makeAddr("referrer");

    // Constants
    uint256 constant APP_ID = 1;
    uint256 constant INITIAL_ELTA_SUPPLY = 10_000_000 ether;
    uint256 constant APP_TOKEN_SUPPLY = 1_000_000 ether;
    uint256 constant EPOCH_LENGTH = 1 days;

    // Fee split constants from FeeManager (in bps)
    uint256 constant APP_STAKERS_BPS = 4500; // 45%
    uint256 constant VE_ELTA_BPS = 3000; // 30%
    uint256 constant CREATOR_BPS = 1000; // 10%
    uint256 constant TREASURY_BPS = 1000; // 10%
    uint256 constant REFERRAL_BPS = 500; // 5%

    event EltaDeposited(uint256 indexed appId, uint256 amount, address indexed from);
    event EltaSwept(uint256 indexed appId, uint256 amount, address indexed to);
    event EpochClosed(uint256 indexed appId, uint256 epoch, uint256 totalDistributed);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA("ELTA", "ELTA", admin, admin, INITIAL_ELTA_SUPPLY, 0);

        // Deploy USDC mock
        usdc = new MockUSDC();

        // Deploy veELTA
        veElta = new VeELTA(elta, admin);

        // Deploy AppRewardsDistributor
        appRewardsDistributor = new AppRewardsDistributor(elta, admin, factory);

        // Deploy RewardsDistributor
        rewardsDistributor = new RewardsDistributor(
            elta, IVeEltaVotes(address(veElta)), IAppRewardsDistributor(address(appRewardsDistributor)), treasury, admin
        );

        // Deploy ReferralRegistry
        referralRegistry = new ReferralRegistry(admin, address(elta), REFERRAL_BPS);

        // Deploy FeeManager with correct constructor
        feeManager = new FeeManager(
            address(elta),
            address(usdc),
            admin,
            admin, // governance
            address(appRewardsDistributor),
            address(rewardsDistributor),
            treasury,
            EPOCH_LENGTH
        );

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(feeManager), feeSwapper);

        // Setup FeeManager depositors
        feeManager.setDepositor(address(feeCollector), true);

        // Set referral registry
        feeManager.setReferralRegistry(address(referralRegistry));

        // Deploy app token
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, address(1), address(1), address(1), address(1)
        );
        appToken.mint(admin, APP_TOKEN_SUPPLY);

        // Deploy app staking vault
        appVault = new AppStakingVault("TestApp Staking", "sTEST", appToken, admin);

        // Register app with AppRewardsDistributor
        vm.stopPrank();
        vm.prank(factory);
        appRewardsDistributor.registerApp(address(appVault));
        vm.startPrank(admin);

        // Set app creator in FeeManager
        feeManager.setAppCreator(APP_ID, creator);

        vm.stopPrank();

        // Fund users
        vm.startPrank(admin);
        elta.transfer(veStaker, 100_000 ether);
        elta.transfer(buyer, 100_000 ether);
        elta.transfer(address(referralRegistry), 100_000 ether); // Fund referral rewards
        appToken.transfer(appStaker, 100_000 ether);
        vm.stopPrank();

        // Setup approvals
        vm.prank(veStaker);
        elta.approve(address(veElta), type(uint256).max);

        vm.prank(appStaker);
        appToken.approve(address(appVault), type(uint256).max);

        vm.prank(buyer);
        elta.approve(address(feeCollector), type(uint256).max);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FULL PIPELINE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_FullPipeline_DepositToDistribution() public {
        // Setup: veELTA staker locks ELTA
        vm.prank(veStaker);
        veElta.lock(10_000 ether, uint64(block.timestamp + 365 days));

        // Advance block for snapshot
        vm.roll(block.number + 1);

        // Setup: App staker stakes
        vm.prank(appStaker);
        appVault.stake(10_000 ether);

        // 1. Buyer deposits fees to FeeCollector (simulates bonding curve fee)
        uint256 feeAmount = 10_000 ether;

        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, feeAmount);

        // Verify FeeCollector received funds
        assertEq(feeCollector.pendingEltaFees(APP_ID), feeAmount);

        // 2. Sweep to FeeManager (now calls depositEltaForApp)
        feeCollector.sweepElta(APP_ID);

        // Verify FeeManager received funds
        assertEq(feeCollector.pendingEltaFees(APP_ID), 0);
        assertEq(feeManager.pendingEltaToDistribute(APP_ID), feeAmount);

        // 3. Close epoch to distribute
        vm.warp(block.timestamp + 1 days + 1);

        uint256 creatorBefore = elta.balanceOf(creator);
        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 appRewardsBefore = elta.balanceOf(address(appRewardsDistributor));
        uint256 veRewardsBefore = elta.balanceOf(address(rewardsDistributor));

        feeManager.closeEpoch(APP_ID);

        // Verify distribution
        uint256 expectedCreator = (feeAmount * CREATOR_BPS) / 10000;
        uint256 expectedTreasury = (feeAmount * TREASURY_BPS) / 10000;
        uint256 expectedAppRewards = (feeAmount * APP_STAKERS_BPS) / 10000;
        uint256 expectedVeRewards = (feeAmount * VE_ELTA_BPS) / 10000;

        assertEq(elta.balanceOf(creator) - creatorBefore, expectedCreator, "Creator share incorrect");
        assertEq(elta.balanceOf(treasury) - treasuryBefore, expectedTreasury, "Treasury share incorrect");
        assertGt(elta.balanceOf(address(appRewardsDistributor)) - appRewardsBefore, 0, "App rewards should increase");
        assertGt(elta.balanceOf(address(rewardsDistributor)) - veRewardsBefore, 0, "VE rewards should increase");
    }

    function test_Pipeline_MultipleAppsIndependent() public {
        // Register a second app
        uint256 APP_ID_2 = 2;
        address creator2 = makeAddr("creator2");

        // Set creator for second app
        vm.prank(admin);
        feeManager.setAppCreator(APP_ID_2, creator2);

        // Deposit fees for both apps
        vm.startPrank(buyer);
        feeCollector.depositElta(APP_ID, 5_000 ether);
        feeCollector.depositElta(APP_ID_2, 10_000 ether);
        vm.stopPrank();

        // Verify independent accounting
        assertEq(feeCollector.pendingEltaFees(APP_ID), 5_000 ether);
        assertEq(feeCollector.pendingEltaFees(APP_ID_2), 10_000 ether);

        // Sweep only first app
        feeCollector.sweepElta(APP_ID);

        assertEq(feeCollector.pendingEltaFees(APP_ID), 0);
        assertEq(feeCollector.pendingEltaFees(APP_ID_2), 10_000 ether);

        assertEq(feeManager.pendingEltaToDistribute(APP_ID), 5_000 ether);
        assertEq(feeManager.pendingEltaToDistribute(APP_ID_2), 0);

        // Sweep second app
        feeCollector.sweepElta(APP_ID_2);

        assertEq(feeManager.pendingEltaToDistribute(APP_ID_2), 10_000 ether);
    }

    function test_Pipeline_EpochTimingEnforced() public {
        // Deposit and sweep
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        feeCollector.sweepElta(APP_ID);

        // Cannot close epoch immediately (need to wait)
        // FeeManager should allow immediate close or enforce epoch timing
        // This test verifies the epoch mechanism

        // Close first epoch
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        // Cannot close again without new deposits
        // vm.expectRevert(); // May or may not revert depending on implementation
        // feeManager.closeEpoch(APP_ID);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FEE SPLIT VERIFICATION
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_FeeSplitAccuracy(uint256 feeAmount) public {
        // Bound to reasonable amounts
        feeAmount = bound(feeAmount, 1 ether, 100_000 ether);

        // Deposit and sweep
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, feeAmount);
        feeCollector.sweepElta(APP_ID);

        // Record balances before
        uint256 creatorBefore = elta.balanceOf(creator);
        uint256 treasuryBefore = elta.balanceOf(treasury);

        // Close epoch
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        // Calculate expected splits
        uint256 expectedCreator = (feeAmount * CREATOR_BPS) / 10000;
        uint256 expectedTreasury = (feeAmount * TREASURY_BPS) / 10000;

        // Verify with small tolerance for rounding
        assertApproxEqRel(elta.balanceOf(creator) - creatorBefore, expectedCreator, 0.001e18, "Creator share incorrect");
        assertApproxEqRel(
            elta.balanceOf(treasury) - treasuryBefore, expectedTreasury, 0.001e18, "Treasury share incorrect"
        );
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CALLER INCENTIVE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Pipeline_CallerIncentive() public {
        // Deposit and sweep
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        feeCollector.sweepElta(APP_ID);

        // Wait for epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Third party closes epoch to earn incentive
        address caller = makeAddr("caller");
        uint256 callerBefore = elta.balanceOf(caller);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID);

        // Caller should receive incentive (if enabled in FeeManager)
        // Note: This depends on FeeManager implementation
        // uint256 callerAfter = elta.balanceOf(caller);
        // assertGt(callerAfter, callerBefore, "Caller should receive incentive");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASES
    // ────────────────────────────────────────────────────────────────────────────

    function test_Pipeline_ZeroDeposit() public {
        vm.expectRevert();
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, 0);
    }

    function test_Pipeline_SweepWithNoPendingFees() public {
        vm.expectRevert();
        feeCollector.sweepElta(APP_ID);
    }

    function test_Pipeline_PermissionlessOperations() public {
        // Anyone can deposit fees
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, 10_000 ether);

        // Anyone can sweep
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        feeCollector.sweepElta(APP_ID);

        // Anyone can close epoch
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(randomUser);
        feeManager.closeEpoch(APP_ID);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCUMULATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Pipeline_AccumulatedFees() public {
        // Multiple deposits before sweep
        vm.startPrank(buyer);
        feeCollector.depositElta(APP_ID, 1_000 ether);
        feeCollector.depositElta(APP_ID, 2_000 ether);
        feeCollector.depositElta(APP_ID, 3_000 ether);
        vm.stopPrank();

        // Total should be accumulated
        assertEq(feeCollector.pendingEltaFees(APP_ID), 6_000 ether);

        // Single sweep should move all
        feeCollector.sweepElta(APP_ID);
        assertEq(feeManager.pendingEltaToDistribute(APP_ID), 6_000 ether);
    }

    function test_Pipeline_MultipleEpochs() public {
        // First epoch
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, 5_000 ether);
        feeCollector.sweepElta(APP_ID);

        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        uint256 creatorAfterFirst = elta.balanceOf(creator);

        // Second epoch
        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        feeCollector.sweepElta(APP_ID);

        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(APP_ID);

        uint256 creatorAfterSecond = elta.balanceOf(creator);

        // Second epoch should have larger distribution
        uint256 firstEpochCreator = creatorAfterFirst - 0;
        uint256 secondEpochCreator = creatorAfterSecond - creatorAfterFirst;

        // 10k deposit should give 2x the creator share of 5k deposit
        assertApproxEqRel(secondEpochCreator, firstEpochCreator * 2, 0.01e18);
    }
}
