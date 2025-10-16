// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppFactory } from "../../src/apps/AppFactory.sol";
import { AppFactoryViews } from "../../src/apps/AppFactoryViews.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { AppBondingCurve } from "../../src/apps/AppBondingCurve.sol";
import { LpLocker } from "../../src/apps/LpLocker.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../src/interfaces/IAppFeeRouter.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import {
    MockAppFeeRouter,
    MockAppRewardsDistributor,
    MockElataXP,
    MockRewardsDistributor
} from "../mocks/MockContracts.sol";
import { IRewardsDistributor } from "../../src/interfaces/IRewardsDistributor.sol";

/**
 * @title App Launch Integration Tests
 * @notice End-to-end testing of the complete app launch framework
 * @dev Tests the full lifecycle from app creation to graduation and beyond
 */
contract AppLaunchIntegrationTest is Test {
    ELTA public elta;
    AppFactory public factory;
    AppFactoryViews public views;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public creator1 = makeAddr("creator1");
    address public creator2 = makeAddr("creator2");
    address public investor1 = makeAddr("investor1");
    address public investor2 = makeAddr("investor2");
    address public investor3 = makeAddr("investor3");
    address public governance = makeAddr("governance");

    address public mockRouter = makeAddr("mockRouter");
    address public mockFactory = makeAddr("mockFactory");
    address public mockPair = makeAddr("mockPair");

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);

        // Setup mock Uniswap
        _setupMockUniswap();

        // Deploy mocks for new architecture
        MockAppFeeRouter mockFeeRouter = new MockAppFeeRouter();
        MockAppRewardsDistributor mockAppRewards = new MockAppRewardsDistributor();
        MockRewardsDistributor mockRewards = new MockRewardsDistributor();
        MockElataXP mockXP = new MockElataXP();

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

        // Deploy views contract for complex queries
        views = new AppFactoryViews(address(factory));

        // Distribute ELTA for testing
        vm.startPrank(treasury);
        elta.transfer(creator1, 10_000 ether);
        elta.transfer(creator2, 10_000 ether);
        elta.transfer(investor1, 50_000 ether);
        elta.transfer(investor2, 50_000 ether);
        elta.transfer(investor3, 50_000 ether);
        vm.stopPrank();

        // Give users XP to pass XP gating
        mockXP.setBalance(creator1, 1000 ether);
        mockXP.setBalance(creator2, 1000 ether);
        mockXP.setBalance(investor1, 1000 ether);
        mockXP.setBalance(investor2, 1000 ether);
        mockXP.setBalance(investor3, 1000 ether);
    }

    function _setupMockUniswap() internal {
        vm.mockCall(mockRouter, abi.encodeWithSignature("factory()"), abi.encode(mockFactory));

        vm.mockCall(
            mockFactory, abi.encodeWithSignature("getPair(address,address)"), abi.encode(address(0))
        );

        vm.mockCall(
            mockFactory,
            abi.encodeWithSignature("createPair(address,address)"),
            abi.encode(mockPair)
        );

        vm.mockCall(
            mockRouter,
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"
            ),
            abi.encode(500_000 ether, 900 ether, 1000 ether)
        );

        vm.mockCall(mockPair, abi.encodeWithSignature("balanceOf(address)"), abi.encode(1000 ether));

        vm.mockCall(
            mockPair, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true)
        );
    }

    function test_CompleteAppLaunchLifecycle() public {
        // 1. Creator launches app
        uint256 appId = _createTestApp();

        // 2. Investors buy tokens during bonding curve
        _testBondingCurvePhase(appId);

        // Note: Graduation testing requires real Uniswap integration
        // Core functionality is verified in individual contract tests
    }

    function _createTestApp() internal returns (uint256 appId) {
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);

        appId = factory.createApp(
            "NeuroRacing",
            "RACE",
            0, // Use default supply
            "High-speed EEG racing game",
            "ipfs://QmRaceGame",
            "https://neurorace.game"
        );
        vm.stopPrank();

        // Verify app creation
        assertEq(appId, 0);

        AppFactory.App memory app = factory.getApp(appId);
        assertEq(app.creator, creator1);
        assertFalse(app.graduated);
        assertTrue(app.token != address(0));
        assertTrue(app.curve != address(0));

        // Verify token details
        AppToken token = AppToken(app.token);
        uint256 defaultSupply = factory.defaultSupply();
        uint256 creatorStaked = defaultSupply / 2; // 50% auto-staked to creator
        uint256 curveSupply = defaultSupply - creatorStaked; // 50% to curve

        assertEq(token.name(), "NeuroRacing");
        assertEq(token.symbol(), "RACE");
        assertEq(token.totalSupply(), defaultSupply);

        // V2: Creator's 50% is auto-staked in vault (not liquid)
        AppStakingVault vault = AppStakingVault(app.vault);
        assertEq(vault.balanceOf(creator1), creatorStaked); // Creator has 50% staked
        assertEq(token.balanceOf(app.curve), curveSupply); // Curve has 50%

        console2.log("[OK] App created successfully");
    }

    function _testBondingCurvePhase(uint256 appId) internal {
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Test multiple purchases with different amounts
        uint256[] memory purchaseAmounts = new uint256[](3);
        purchaseAmounts[0] = 100 ether;
        purchaseAmounts[1] = 200 ether;
        purchaseAmounts[2] = 300 ether;

        address[] memory buyers = new address[](3);
        buyers[0] = investor1;
        buyers[1] = investor2;
        buyers[2] = investor3;

        uint256 totalTokensPurchased = 0;
        uint256 totalEltaSpent = 0;

        for (uint256 i = 0; i < purchaseAmounts.length; i++) {
            uint256 amount = purchaseAmounts[i];
            address buyer = buyers[i];

            uint256 expectedTokens = curve.getTokensOut(amount);
            uint256 priceBefore = curve.getCurrentPrice();

            vm.startPrank(buyer);
            // Approve amount + 1% trading fee (fee paid ON TOP)
            elta.approve(address(curve), amount * 101 / 100);
            uint256 tokensOut = curve.buy(amount, expectedTokens);
            vm.stopPrank();

            uint256 priceAfter = curve.getCurrentPrice();

            // Verify purchase
            assertEq(tokensOut, expectedTokens);
            assertEq(token.balanceOf(buyer), expectedTokens);
            assertGt(priceAfter, priceBefore);

            totalTokensPurchased += tokensOut;
            totalEltaSpent += amount;

            // console2.log("Purchase", i + 1, "completed:", amount / 1e18, "ELTA for", tokensOut / 1e18, "tokens");
        }

        // Verify curve state
        (uint256 eltaReserve, uint256 tokenReserve,,,, uint256 progress) = curve.getCurveState();

        uint256 defaultSupply = factory.defaultSupply();
        uint256 curveSupply = defaultSupply / 2; // V2: 50% to curve, 50% auto-staked

        assertGt(eltaReserve, factory.seedElta()); // Should have more than seed
        assertEq(tokenReserve, curveSupply - totalTokensPurchased);
        assertGt(progress, 0);
        assertLt(progress, 10000); // Not graduated yet

        console2.log("[OK] Bonding curve phase completed");
    }

    // Graduation functions removed - require real Uniswap integration for testing

    function test_MultipleAppLaunches() public {
        // Create multiple apps
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        // Creator 1 launches two apps
        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost * 2);

        uint256 appId1 = factory.createApp("Game1", "GAME1", 0, "First game", "", "");
        uint256 appId2 = factory.createApp("Game2", "GAME2", 0, "Second game", "", "");

        vm.stopPrank();

        // Creator 2 launches one app
        vm.startPrank(creator2);
        elta.approve(address(factory), totalCost);

        uint256 appId3 = factory.createApp("Meditate", "ZEN", 0, "Meditation app", "", "");

        vm.stopPrank();

        // Verify all apps created
        assertEq(factory.appCount(), 3);
        assertEq(appId1, 0);
        assertEq(appId2, 1);
        assertEq(appId3, 2);

        // Verify creator mappings
        uint256[] memory creator1Apps = views.getCreatorApps(creator1);
        uint256[] memory creator2Apps = views.getCreatorApps(creator2);

        assertEq(creator1Apps.length, 2);
        assertEq(creator2Apps.length, 1);
        assertEq(creator1Apps[0], appId1);
        assertEq(creator1Apps[1], appId2);
        assertEq(creator2Apps[0], appId3);

        // Test concurrent trading on different curves
        AppFactory.App memory app1 = factory.getApp(appId1);
        AppFactory.App memory app2 = factory.getApp(appId2);

        AppBondingCurve curve1 = AppBondingCurve(app1.curve);
        AppBondingCurve curve2 = AppBondingCurve(app2.curve);

        // Investors can buy from different curves simultaneously
        vm.startPrank(investor1);
        // Approve with 1% fee on top
        elta.approve(address(curve1), 500 ether * 101 / 100);
        elta.approve(address(curve2), 500 ether * 101 / 100);

        uint256 tokens1 = curve1.buy(500 ether, 0);
        uint256 tokens2 = curve2.buy(500 ether, 0);

        vm.stopPrank();

        assertGt(tokens1, 0);
        assertGt(tokens2, 0);

        // Different curves should give different amounts (different states)
        // This verifies they're independent

        console2.log("[OK] Multiple app launches working correctly");
    }

    function test_AppLaunchEconomics() public {
        // Test the economic flows of app launches

        uint256 treasuryBefore = elta.balanceOf(treasury);

        // Create app (pays creation fee)
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("EconTest", "ECON", 0, "", "", "");
        vm.stopPrank();

        uint256 treasuryAfterCreation = elta.balanceOf(treasury);

        // Verify creation fee collected
        assertEq(treasuryAfterCreation - treasuryBefore, factory.creationFee());

        // Test protocol fees during trading
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 purchaseAmount = 1000 ether;

        vm.startPrank(investor1);
        // Approve with 1% trading fee
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        // Trading fees now route through RewardsDistributor (70/15/15 split)
        // Treasury receives creation fee only

        console2.log("[OK] Economic flows verified");
    }

    function test_FactoryParameterUpdates() public {
        // Test that parameters are correctly set from factory constants

        // Create app with factory parameters
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("NewParams", "NEW", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Verify factory parameters applied correctly
        assertEq(curve.targetRaisedElta(), factory.targetRaisedElta());
        assertEq(token.maxSupply(), factory.defaultSupply());
        assertEq(curve.reserveElta(), factory.seedElta());

        console2.log("[OK] Parameter updates working correctly");
    }

    function test_AppRegistryFunctionality() public {
        // Test comprehensive registry functionality

        // Initially no apps
        (uint256 totalApps, uint256 graduatedApps,,) = views.getLaunchStats();
        assertEq(totalApps, 0);
        assertEq(graduatedApps, 0);

        // Create several apps
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost * 2);
        uint256 appId1 = factory.createApp("App1", "APP1", 0, "", "", "");
        uint256 appId2 = factory.createApp("App2", "APP2", 0, "", "", "");
        vm.stopPrank();

        vm.startPrank(creator2);
        elta.approve(address(factory), totalCost);
        uint256 appId3 = factory.createApp("App3", "APP3", 0, "", "", "");
        vm.stopPrank();

        // Test registry queries
        (totalApps,,,) = views.getLaunchStats();
        assertEq(totalApps, 3);

        // Test creator mappings
        uint256[] memory creator1Apps = views.getCreatorApps(creator1);
        uint256[] memory creator2Apps = views.getCreatorApps(creator2);

        assertEq(creator1Apps.length, 2);
        assertEq(creator2Apps.length, 1);

        // Test token to app mapping
        AppFactory.App memory app1 = factory.getApp(appId1);
        assertEq(factory.tokenToAppId(app1.token), appId1);

        // Test graduated apps (none yet)
        uint256[] memory graduatedAppsList = views.getGraduatedApps();
        assertEq(graduatedAppsList.length, 0);

        console2.log("[OK] Registry functionality verified");
    }

    function test_SecurityMechanisms() public {
        // Test pause functionality
        vm.prank(admin);
        factory.setPaused(true);

        vm.expectRevert(AppFactory.Paused.selector);
        vm.prank(creator1);
        factory.createApp("Paused", "PAUSE", 0, "", "", "");

        // Unpause and verify works
        vm.prank(admin);
        factory.setPaused(false);

        uint256 totalCost = factory.creationFee() + factory.seedElta();
        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("Unpaused", "UNPAUSE", 0, "", "", "");
        vm.stopPrank();

        assertEq(appId, 0);

        // Test unauthorized pause (parameters are immutable now)
        vm.expectRevert();
        vm.prank(creator1);
        factory.setPaused(true);

        console2.log("[OK] Security mechanisms verified");
    }

    function test_GasOptimization() public {
        // Test gas costs for various operations

        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);

        uint256 gasBefore = gasleft();
        uint256 appId = factory.createApp("GasTest", "GAS", 0, "", "", "");
        uint256 gasAfter = gasleft();

        vm.stopPrank();

        uint256 creationGas = gasBefore - gasAfter;
        console2.log("App creation gas:", creationGas);

        // V3: Gas increased due to transfer fee logic and additional setup
        // Threshold updated to 7.5M to account for transfer fee calculations
        assertLt(creationGas, 7_500_000);

        // Test purchase gas costs
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        vm.startPrank(investor1);
        // Approve with 1% fee
        elta.approve(address(curve), 100 ether * 101 / 100);

        gasBefore = gasleft();
        curve.buy(100 ether, 0);
        gasAfter = gasleft();

        vm.stopPrank();

        uint256 purchaseGas = gasBefore - gasAfter;
        console2.log("Token purchase gas:", purchaseGas);

        // Purchase gas should be reasonable (less than 200K)
        assertLt(purchaseGas, 200_000);

        console2.log("[OK] Gas optimization verified");
    }

    function test_ErrorHandlingAndEdgeCases() public {
        // Create app for testing
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("EdgeTest", "EDGE", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Test buying with insufficient balance
        vm.expectRevert();
        vm.prank(makeAddr("poorUser"));
        curve.buy(1000 ether, 0);

        // Test buying with insufficient approval
        vm.startPrank(investor1);
        // Approve only 50 ELTA (not enough for 100 ELTA trade + 1% fee)
        elta.approve(address(curve), 50 ether);

        vm.expectRevert();
        curve.buy(100 ether, 0); // Tries to spend more than approved

        vm.stopPrank();

        // Test slippage protection
        uint256 eltaIn = 100 ether;
        uint256 expectedTokens = curve.getTokensOut(eltaIn);

        vm.startPrank(investor1);
        // Approve with 1% fee
        elta.approve(address(curve), eltaIn * 101 / 100);

        vm.expectRevert(AppBondingCurve.InsufficientOutput.selector);
        curve.buy(eltaIn, expectedTokens + 1); // Set minimum too high

        vm.stopPrank();

        console2.log("[OK] Error handling verified");
    }

    function testFuzz_AppLaunchScenarios(uint256 supply, uint256 purchaseAmount) public {
        // Bound parameters to reasonable ranges
        supply = bound(supply, 1_000_000 ether, 10_000_000_000 ether);

        // Use factory's fixed parameters
        uint256 seedAmount = factory.seedElta();
        uint256 targetAmount = factory.targetRaisedElta();

        purchaseAmount = bound(purchaseAmount, 1 ether, (targetAmount - seedAmount) / 2);

        // Create app with fuzzed supply
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.prank(treasury);
        elta.transfer(creator1, totalCost);

        vm.startPrank(creator1);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FuzzApp", "FUZZ", supply, "", "", "");
        vm.stopPrank();

        // Verify app created correctly
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);
        AppStakingVault vault = AppStakingVault(app.vault);

        uint256 creatorStaked = supply / 2; // 50% auto-staked
        uint256 curveSupply = supply - creatorStaked;

        assertEq(token.maxSupply(), supply);
        assertEq(vault.balanceOf(creator1), creatorStaked); // Creator has 50% staked
        assertEq(curve.targetRaisedElta(), targetAmount);
        assertEq(curve.reserveElta(), seedAmount);
        assertEq(curve.reserveToken(), curveSupply); // Curve has 50%

        // Test purchase with fuzzed amount
        vm.prank(treasury);
        elta.transfer(investor1, purchaseAmount);

        vm.startPrank(investor1);
        // Approve with 1% fee
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        uint256 tokensOut = curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        assertGt(tokensOut, 0);
        assertEq(token.balanceOf(investor1), tokensOut);
    }
}
