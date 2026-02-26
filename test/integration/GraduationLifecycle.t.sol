// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {AppFactory} from "../../src/apps/AppFactory.sol";
import {AppFactoryViews} from "../../src/apps/AppFactoryViews.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {AppVestingWallet} from "../../src/vesting/AppVestingWallet.sol";
import {AppEcosystemVault} from "../../src/vesting/AppEcosystemVault.sol";
import {LpLocker} from "../../src/apps/LpLocker.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IRewardsDistributor} from "../../src/interfaces/IRewardsDistributor.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {ELTA} from "elta/ELTA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    MockAppFeeRouter,
    MockAppRewardsDistributor,
    MockElataPoints,
    MockRewardsDistributor
} from "../mocks/MockContracts.sol";
import "forge-std/Test.sol";

/**
 * @title Graduation Lifecycle Integration Test
 * @notice End-to-end test of the complete app journey from creation to graduation
 * @dev Tests the full lifecycle:
 *      1. App creation via AppFactory
 *      2. Multiple users trading on bonding curve
 *      3. Graduation trigger at threshold
 *      4. LP creation and locking
 *      5. Post-graduation state verification
 *      6. Fee distribution through the pipeline
 */
contract GraduationLifecycleTest is Test {
    ELTA public elta;
    AppFactory public factory;
    AppFactoryViews public views;
    FeeCollector public feeCollector;
    FeeSwapper public feeSwapper;
    AppRegistry public registry;
    ContributorSplitFactory public splitFactory;
    MockAppFeeRouter public mockFeeRouter;
    MockAppRewardsDistributor public mockAppRewards;
    MockRewardsDistributor public mockRewards;
    MockElataPoints public mockXP;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public feeManager = makeAddr("feeManager");
    address public governance = makeAddr("governance");

    // Creator
    address public creator = makeAddr("creator");

    // Multiple investors for realistic simulation
    address public investor1 = makeAddr("investor1");
    address public investor2 = makeAddr("investor2");
    address public investor3 = makeAddr("investor3");
    address public investor4 = makeAddr("investor4");
    address public investor5 = makeAddr("investor5");
    address public investor6 = makeAddr("investor6");
    address public investor7 = makeAddr("investor7");
    address public investor8 = makeAddr("investor8");
    address public investor9 = makeAddr("investor9");
    address public investor10 = makeAddr("investor10");

    // Mock Uniswap
    address public mockRouter = makeAddr("mockRouter");
    address public mockUniFactory = makeAddr("mockUniFactory");
    address public mockPair = makeAddr("mockPair");

    // Constants from factory
    uint256 public constant SEED_ELTA = 100 ether;
    uint256 public constant TARGET_RAISED = 42_000 ether;
    uint256 public constant DEFAULT_SUPPLY = 10_000_000 ether;
    uint256 public constant CREATION_FEE = 10 ether;

    function setUp() public {
        // Deploy ELTA token
        elta = new ELTA(treasury);

        // Setup mock Uniswap
        _setupMockUniswap();

        // Deploy mocks
        mockFeeRouter = new MockAppFeeRouter();
        mockAppRewards = new MockAppRewardsDistributor();
        mockRewards = new MockRewardsDistributor();
        mockXP = new MockElataPoints();

        // Deploy AppFactory
        factory = new AppFactory(
            elta,
            IUniswapV2Router02(mockRouter),
            treasury,
            IAppFeeRouter(address(mockFeeRouter)),
            IAppRewardsDistributor(address(mockAppRewards)),
            IRewardsDistributor(address(mockRewards)),
            mockXP,
            governance,
            admin
        );

        // Configure vNext dependencies (required by createApp wrapper).
        registry = new AppRegistry(governance, address(factory));
        splitFactory = new ContributorSplitFactory(governance, address(factory));
        feeSwapper = new FeeSwapper(address(elta), admin, governance, treasury, address(registry));

        vm.startPrank(admin);
        factory.setAppRegistry(address(registry));
        factory.setContributorSplitFactory(address(splitFactory));
        factory.setFeeSwapper(address(feeSwapper));
        vm.stopPrank();

        // Deploy FeeCollector (route ELTA sweeps + app token sweeps to FeeSwapper).
        feeCollector = new FeeCollector(address(elta), admin, address(feeSwapper), address(feeSwapper));

        // Set FeeCollector on factory
        vm.prank(admin);
        factory.setFeeCollector(address(feeCollector));

        // Deploy views
        views = new AppFactoryViews(address(factory));

        // Distribute ELTA to all participants
        _distributeELTA();

        // Give all users XP to pass gating
        _setupXP();
    }

    function _setupMockUniswap() internal {
        // Mock router.factory()
        vm.mockCall(mockRouter, abi.encodeWithSignature("factory()"), abi.encode(mockUniFactory));

        // Mock factory.getPair() - returns 0 initially (no pair exists)
        vm.mockCall(mockUniFactory, abi.encodeWithSignature("getPair(address,address)"), abi.encode(address(0)));

        // Mock factory.createPair()
        vm.mockCall(mockUniFactory, abi.encodeWithSignature("createPair(address,address)"), abi.encode(mockPair));

        // Mock router.addLiquidity() - returns amounts
        vm.mockCall(
            mockRouter,
            abi.encodeWithSignature("addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"),
            abi.encode(5_000_000 ether, 42_000 ether, 1000 ether)
        );

        // Mock pair.balanceOf() - LP tokens received
        vm.mockCall(mockPair, abi.encodeWithSignature("balanceOf(address)"), abi.encode(1000 ether));

        // Mock pair.transfer()
        vm.mockCall(mockPair, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));

        // Mock pair.approve()
        vm.mockCall(mockPair, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
    }

    function _distributeELTA() internal {
        vm.startPrank(treasury);

        // Creator needs creation fee + seed ELTA
        elta.transfer(creator, 1_000 ether);

        // Each investor gets enough to participate
        elta.transfer(investor1, 10_000 ether);
        elta.transfer(investor2, 10_000 ether);
        elta.transfer(investor3, 10_000 ether);
        elta.transfer(investor4, 10_000 ether);
        elta.transfer(investor5, 10_000 ether);
        elta.transfer(investor6, 10_000 ether);
        elta.transfer(investor7, 10_000 ether);
        elta.transfer(investor8, 10_000 ether);
        elta.transfer(investor9, 10_000 ether);
        elta.transfer(investor10, 10_000 ether);

        vm.stopPrank();
    }

    function _setupXP() internal {
        mockXP.setBalance(creator, 1000 ether);
        mockXP.setBalance(investor1, 1000 ether);
        mockXP.setBalance(investor2, 1000 ether);
        mockXP.setBalance(investor3, 1000 ether);
        mockXP.setBalance(investor4, 1000 ether);
        mockXP.setBalance(investor5, 1000 ether);
        mockXP.setBalance(investor6, 1000 ether);
        mockXP.setBalance(investor7, 1000 ether);
        mockXP.setBalance(investor8, 1000 ether);
        mockXP.setBalance(investor9, 1000 ether);
        mockXP.setBalance(investor10, 1000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MAIN LIFECYCLE TEST
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CompleteGraduationLifecycle() public {
        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 1: App Creation
        // ─────────────────────────────────────────────────────────────────────────

        uint256 appId = _phase1_CreateApp();
        AppFactory.App memory app = factory.getApp(appId);

        console2.log("=== PHASE 1: App Created ===");
        console2.log("App ID:", appId);
        console2.log("Token:", app.token);
        console2.log("Curve:", app.curve);
        console2.log("Vesting Wallet:", app.vestingWallet);
        console2.log("Ecosystem Vault:", app.ecosystemVault);

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 2: Bonding Curve Trading
        // ─────────────────────────────────────────────────────────────────────────

        _phase2_BondingCurveTrading(appId);

        console2.log("=== PHASE 2: Trading Complete ===");

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 3: Graduation
        // ─────────────────────────────────────────────────────────────────────────

        _phase3_Graduation(appId);

        console2.log("=== PHASE 3: Graduated ===");

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 4: Post-Graduation Verification
        // ─────────────────────────────────────────────────────────────────────────

        _phase4_PostGraduationVerification(appId);

        console2.log("=== PHASE 4: Verification Complete ===");

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 5: Fee Distribution
        // ─────────────────────────────────────────────────────────────────────────

        _phase5_FeeDistribution(appId);

        console2.log("=== PHASE 5: Fees Distributed ===");
        console2.log("");
        console2.log("=== FULL GRADUATION LIFECYCLE COMPLETE ===");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 1: App Creation
    // ═══════════════════════════════════════════════════════════════════════════

    function _phase1_CreateApp() internal returns (uint256 appId) {
        uint256 totalCost = CREATION_FEE + SEED_ELTA;

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);

        appId = factory.createApp(
            "GraduationTest",
            "GRAD",
            0, // Use default supply
            "Testing full graduation lifecycle",
            "ipfs://test",
            "https://test.com",
            new address[](0)
        );
        vm.stopPrank();

        // Verify creation
        assertEq(appId, 0, "First app should have ID 0");

        AppFactory.App memory app = factory.getApp(appId);
        assertEq(app.creator, creator, "Creator mismatch");
        assertFalse(app.graduated, "Should not be graduated yet");
        assertTrue(app.token != address(0), "Token not deployed");
        assertTrue(app.curve != address(0), "Curve not deployed");
        assertTrue(app.vestingWallet != address(0), "Vesting wallet not deployed");
        assertTrue(app.ecosystemVault != address(0), "Ecosystem vault not deployed");

        // Verify token allocation (50/25/25)
        AppToken token = AppToken(app.token);
        uint256 curveShare = DEFAULT_SUPPLY / 2; // 50%
        uint256 vestingShare = DEFAULT_SUPPLY / 4; // 25%
        uint256 ecosystemShare = DEFAULT_SUPPLY - curveShare - vestingShare; // 25%

        assertEq(token.balanceOf(app.curve), curveShare, "Curve allocation wrong");
        assertEq(token.balanceOf(app.vestingWallet), vestingShare, "Vesting allocation wrong");
        assertEq(token.balanceOf(app.ecosystemVault), ecosystemShare, "Ecosystem allocation wrong");

        return appId;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 2: Bonding Curve Trading
    // ═══════════════════════════════════════════════════════════════════════════

    function _phase2_BondingCurveTrading(uint256 appId) internal {
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Activate curve (warp past activation delay)
        vm.warp(block.timestamp + 1 hours + 1);
        curve.activate();

        // Verify curve is active
        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.ACTIVE), "Curve not active");

        // Track total purchases
        uint256 totalEltaIn = 0;
        uint256 totalTokensOut = 0;

        // Simulate multiple users trading
        address[10] memory investors = [
            investor1,
            investor2,
            investor3,
            investor4,
            investor5,
            investor6,
            investor7,
            investor8,
            investor9,
            investor10
        ];

        // Each investor buys in rounds to simulate realistic trading
        for (uint256 round = 0; round < 4; round++) {
            for (uint256 i = 0; i < investors.length; i++) {
                address investor = investors[i];

                // Skip if curve would graduate (save that for phase 3)
                (uint256 eltaReserve,,,,, uint256 progress) = curve.getCurveState();
                if (progress >= 9500) break; // Near graduation

                // Buy varying amounts
                uint256 buyAmount = 500 ether + (i * 100 ether) + (round * 200 ether);

                // Don't exceed remaining to graduation
                uint256 remaining = TARGET_RAISED - eltaReserve;
                if (buyAmount > remaining - 1000 ether) {
                    buyAmount = remaining - 1000 ether; // Leave room
                }

                if (buyAmount < 1 ether) continue;

                uint256 expectedTokens = curve.getTokensOut(buyAmount);
                if (expectedTokens == 0) continue;

                vm.startPrank(investor);
                // Approve with 1% trading fee buffer
                elta.approve(address(curve), buyAmount * 102 / 100);
                uint256 tokensOut = curve.buy(buyAmount, expectedTokens * 99 / 100, address(0));
                vm.stopPrank();

                totalEltaIn += buyAmount;
                totalTokensOut += tokensOut;

                // Verify investor received tokens
                assertGt(AppToken(app.token).balanceOf(investor), 0, "Investor should have tokens");
            }
        }

        // Verify curve state after trading
        (uint256 finalEltaReserve, uint256 finalTokenReserve,,,, uint256 finalProgress) = curve.getCurveState();

        assertGt(finalEltaReserve, SEED_ELTA, "ELTA reserve should have grown");
        assertLt(finalTokenReserve, DEFAULT_SUPPLY / 2, "Token reserve should have decreased");
        assertGt(finalProgress, 0, "Progress should be > 0");
        assertLt(finalProgress, 10000, "Should not be graduated yet");

        console2.log("Total ELTA invested:", totalEltaIn / 1e18);
        console2.log("Total tokens distributed:", totalTokensOut / 1e18);
        console2.log("Graduation progress:", finalProgress, "bps");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 3: Graduation
    // ═══════════════════════════════════════════════════════════════════════════

    function _phase3_Graduation(uint256 appId) internal {
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Get current state
        (uint256 eltaReserveBefore,,,,,) = curve.getCurveState();

        // Calculate how much more ELTA needed to graduate
        uint256 eltaNeeded = TARGET_RAISED - eltaReserveBefore;

        // Final purchase to trigger graduation
        vm.startPrank(investor1);
        // Need extra ELTA for the big buy
        vm.stopPrank();

        vm.prank(treasury);
        elta.transfer(investor1, eltaNeeded * 2);

        vm.startPrank(investor1);
        elta.approve(address(curve), eltaNeeded * 102 / 100);

        // This should trigger graduation
        curve.buy(eltaNeeded, 0, address(0));
        vm.stopPrank();

        // Verify graduation happened
        assertTrue(curve.graduated(), "Curve should be graduated");
        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.GRADUATED), "State should be GRADUATED");

        // Verify factory state updated
        app = factory.getApp(appId);
        assertTrue(app.graduated, "Factory should show graduated");
        assertGt(app.graduatedAt, 0, "Graduation time should be set");
        assertTrue(app.pair != address(0), "Pair should be set");
        assertTrue(app.locker != address(0), "Locker should be set");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 4: Post-Graduation Verification
    // ═══════════════════════════════════════════════════════════════════════════

    function _phase4_PostGraduationVerification(uint256 appId) internal {
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Verify LP data
        address pair = curve.pair();
        address locker = curve.locker();
        uint256 unlockAt = curve.lpUnlockAt();

        assertEq(pair, app.pair, "Pair mismatch");
        assertEq(locker, app.locker, "Locker mismatch");
        assertGt(unlockAt, block.timestamp, "LP should be locked");

        // Verify graduated apps list
        uint256[] memory graduatedApps = views.getGraduatedApps();
        assertEq(graduatedApps.length, 1, "Should have 1 graduated app");
        assertEq(graduatedApps[0], appId, "Graduated app ID mismatch");

        // Verify curve is closed (state is GRADUATED, so onlyActive modifier fails with NotActive)
        vm.startPrank(investor1);
        elta.approve(address(curve), 100 ether);

        vm.expectRevert(AppBondingCurve.NotActive.selector);
        curve.buy(100 ether, 0, address(0));
        vm.stopPrank();

        // Verify token distribution is final
        assertGt(app.totalRaised, 0, "Total raised should be recorded");
        assertGt(app.finalSupply, 0, "Final supply should be recorded");

        console2.log("LP Pair:", pair);
        console2.log("LP Locker:", locker);
        console2.log("LP Unlock At:", unlockAt);
        console2.log("Total Raised:", app.totalRaised / 1e18, "ELTA");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PHASE 5: Fee Distribution
    // ═══════════════════════════════════════════════════════════════════════════

    function _phase5_FeeDistribution(uint256 appId) internal {
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Check pending fees in curve
        uint256 pendingFees = curve.pendingFees();
        console2.log("Pending fees in curve:", pendingFees / 1e18, "ELTA");

        // Sweep fees to FeeCollector
        if (pendingFees > 0 && curve.feeCollector() != address(0)) {
            uint256 feeCollectorBefore = elta.balanceOf(address(feeCollector));

            curve.sweepFees();

            uint256 feeCollectorAfter = elta.balanceOf(address(feeCollector));
            uint256 feesCollected = feeCollectorAfter - feeCollectorBefore;

            console2.log("Fees swept to collector:", feesCollected / 1e18, "ELTA");

            // Verify fees reached collector
            assertGt(
                feeCollector.pendingEltaFees(appId, FeeKind.TRADING_FEE), 0, "FeeCollector should have pending fees"
            );
        }

        // Note: Full fee pipeline (FeeCollector -> FeeManager -> RewardsDistributor)
        // requires real contracts, tested in FeePipeline.t.sol
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL LIFECYCLE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_VestingWalletIntegration() public {
        uint256 appId = _phase1_CreateApp();
        AppFactory.App memory app = factory.getApp(appId);

        AppVestingWallet vesting = AppVestingWallet(app.vestingWallet);
        AppToken token = AppToken(app.token);

        // Verify vesting parameters
        assertEq(vesting.beneficiary(), creator, "Beneficiary should be creator");
        assertEq(vesting.appId(), appId, "App ID mismatch");

        // Verify tokens are in vesting
        uint256 vestingBalance = token.balanceOf(address(vesting));
        assertEq(vestingBalance, DEFAULT_SUPPLY / 4, "Vesting should have 25%");

        // Before cliff, nothing releasable
        assertEq(vesting.releasable(), 0, "Nothing releasable before cliff");

        // Warp past cliff
        vm.warp(block.timestamp + 91 days);

        // After cliff, some tokens releasable
        uint256 releasable = vesting.releasable();
        assertGt(releasable, 0, "Should have releasable tokens after cliff");

        // Release tokens
        vesting.release();
        assertGt(token.balanceOf(creator), 0, "Creator should receive vested tokens");
    }

    function test_EcosystemVaultIntegration() public {
        uint256 appId = _phase1_CreateApp();
        AppFactory.App memory app = factory.getApp(appId);

        AppEcosystemVault ecosystem = AppEcosystemVault(app.ecosystemVault);
        AppToken token = AppToken(app.token);

        // Verify vault parameters
        assertEq(ecosystem.appId(), appId, "App ID mismatch");

        // Verify tokens are in ecosystem vault
        uint256 ecosystemBalance = token.balanceOf(address(ecosystem));
        uint256 expectedEcosystem = DEFAULT_SUPPLY - (DEFAULT_SUPPLY / 2) - (DEFAULT_SUPPLY / 4);
        assertEq(ecosystemBalance, expectedEcosystem, "Ecosystem should have ~25%");

        // Creator can withdraw from ecosystem vault
        uint256 withdrawAmount = 1000 ether;

        vm.prank(creator);
        ecosystem.withdraw(creator, withdrawAmount);

        assertEq(token.balanceOf(creator), withdrawAmount, "Creator should receive ecosystem tokens");
    }

    function test_MultipleAppsIndependentGraduation() public {
        // Create first app
        uint256 appId1 = _createAppForAddress(creator, "App1", "APP1");

        // Create second app with different creator
        address creator2 = makeAddr("creator2");
        vm.prank(treasury);
        elta.transfer(creator2, 1000 ether);
        mockXP.setBalance(creator2, 1000 ether);

        uint256 appId2 = _createAppForAddress(creator2, "App2", "APP2");

        // Verify both apps exist independently
        assertEq(factory.appCount(), 2, "Should have 2 apps");

        AppFactory.App memory app1 = factory.getApp(appId1);
        AppFactory.App memory app2 = factory.getApp(appId2);

        assertTrue(app1.token != app2.token, "Tokens should be different");
        assertTrue(app1.curve != app2.curve, "Curves should be different");

        // Activate both curves
        vm.warp(block.timestamp + 1 hours + 1);
        AppBondingCurve(app1.curve).activate();
        AppBondingCurve(app2.curve).activate();

        // Trade on app1 only
        vm.startPrank(investor1);
        elta.approve(app1.curve, 1000 ether);
        AppBondingCurve(app1.curve).buy(500 ether, 0, address(0));
        vm.stopPrank();

        // Verify app2 is unaffected
        (uint256 eltaReserve2,,,,,) = AppBondingCurve(app2.curve).getCurveState();
        assertEq(eltaReserve2, SEED_ELTA, "App2 should be unchanged");

        // Silence unused variable warnings
        assertTrue(appId1 == 0);
        assertTrue(appId2 == 1);
    }

    function _createAppForAddress(address _creator, string memory name, string memory symbol)
        internal
        returns (uint256)
    {
        uint256 totalCost = CREATION_FEE + SEED_ELTA;

        vm.startPrank(_creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp(name, symbol, 0, "", "", "", new address[](0));
        vm.stopPrank();

        return appId;
    }
}
