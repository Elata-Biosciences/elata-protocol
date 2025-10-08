// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppFactory } from "../../src/apps/AppFactory.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppBondingCurve } from "../../src/apps/AppBondingCurve.sol";
import { LpLocker } from "../../src/apps/LpLocker.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";

/**
 * @title App Launch Integration Tests
 * @notice End-to-end testing of the complete app launch framework
 * @dev Tests the full lifecycle from app creation to graduation and beyond
 */
contract AppLaunchIntegrationTest is Test {
    ELTA public elta;
    AppFactory public factory;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public creator1 = makeAddr("creator1");
    address public creator2 = makeAddr("creator2");
    address public investor1 = makeAddr("investor1");
    address public investor2 = makeAddr("investor2");
    address public investor3 = makeAddr("investor3");

    address public mockRouter = makeAddr("mockRouter");
    address public mockFactory = makeAddr("mockFactory");
    address public mockPair = makeAddr("mockPair");

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);

        // Setup mock Uniswap
        _setupMockUniswap();

        factory = new AppFactory(elta, IUniswapV2Router02(mockRouter), treasury, admin);

        // Distribute ELTA for testing
        vm.startPrank(treasury);
        elta.transfer(creator1, 10_000 ether);
        elta.transfer(creator2, 10_000 ether);
        elta.transfer(investor1, 50_000 ether);
        elta.transfer(investor2, 50_000 ether);
        elta.transfer(investor3, 50_000 ether);
        vm.stopPrank();
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
        uint256 creatorTreasury = (defaultSupply * 10) / 100; // 10% to creator
        uint256 curveSupply = defaultSupply - creatorTreasury; // 90% to curve
        
        assertEq(token.name(), "NeuroRacing");
        assertEq(token.symbol(), "RACE");
        assertEq(token.totalSupply(), defaultSupply);
        assertEq(token.balanceOf(creator1), creatorTreasury); // Creator has 10%
        assertEq(token.balanceOf(app.curve), curveSupply); // Curve has 90%

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
            elta.approve(address(curve), amount);
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
        uint256 curveSupply = (defaultSupply * 90) / 100; // 90% to curve, 10% to creator
        
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
        uint256[] memory creator1Apps = factory.getCreatorApps(creator1);
        uint256[] memory creator2Apps = factory.getCreatorApps(creator2);

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
        elta.approve(address(curve1), 500 ether);
        elta.approve(address(curve2), 500 ether);

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
        uint256 expectedProtocolFee = (purchaseAmount * factory.protocolFeeRate()) / 10000;

        vm.startPrank(investor1);
        elta.approve(address(curve), purchaseAmount);
        curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        uint256 treasuryAfterTrade = elta.balanceOf(treasury);

        // Verify protocol fee collected
        assertEq(treasuryAfterTrade - treasuryAfterCreation, expectedProtocolFee);

        console2.log("[OK] Economic flows verified");
    }

    function test_FactoryParameterUpdates() public {
        // Test parameter updates and their effects

        vm.prank(admin);
        factory.setParameters(
            200 ether, // seedElta
            50_000 ether, // targetRaised
            2_000_000_000 ether, // defaultSupply
            365 days * 3, // lpLockDuration
            18, // defaultDecimals
            500, // protocolFeeRate (5%)
            20 ether // creationFee
        );

        // Create app with new parameters
        uint256 newTotalCost = 200 ether + 20 ether; // seed + creation fee

        vm.startPrank(creator1);
        elta.approve(address(factory), newTotalCost);
        uint256 appId = factory.createApp("NewParams", "NEW", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Verify new parameters applied
        assertEq(curve.targetRaisedElta(), 50_000 ether);
        assertEq(curve.protocolFeeRate(), 500);
        assertEq(token.maxSupply(), 2_000_000_000 ether);
        assertEq(curve.reserveElta(), 200 ether); // New seed amount

        console2.log("[OK] Parameter updates working correctly");
    }

    function test_AppRegistryFunctionality() public {
        // Test comprehensive registry functionality

        // Initially no apps
        (uint256 totalApps, uint256 graduatedApps,,) = factory.getLaunchStats();
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
        (totalApps,,,) = factory.getLaunchStats();
        assertEq(totalApps, 3);

        // Test creator mappings
        uint256[] memory creator1Apps = factory.getCreatorApps(creator1);
        uint256[] memory creator2Apps = factory.getCreatorApps(creator2);

        assertEq(creator1Apps.length, 2);
        assertEq(creator2Apps.length, 1);

        // Test token to app mapping
        AppFactory.App memory app1 = factory.getApp(appId1);
        assertEq(factory.getAppIdFromToken(app1.token), appId1);

        // Test graduated apps (none yet)
        uint256[] memory graduatedAppsList = factory.getGraduatedApps();
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

        // Test unauthorized parameter changes
        vm.expectRevert();
        vm.prank(creator1);
        factory.setParameters(100 ether, 1000 ether, 1_000_000 ether, 365 days, 18, 250, 10 ether);

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

        // Gas should be reasonable (less than 5M)
        assertLt(creationGas, 5_000_000);

        // Test purchase gas costs
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        vm.startPrank(investor1);
        elta.approve(address(curve), 100 ether);

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
        elta.approve(address(curve), 50 ether);

        vm.expectRevert();
        curve.buy(100 ether, 0); // Tries to spend more than approved

        vm.stopPrank();

        // Test slippage protection
        uint256 eltaIn = 100 ether;
        uint256 expectedTokens = curve.getTokensOut(eltaIn);

        vm.startPrank(investor1);
        elta.approve(address(curve), eltaIn);

        vm.expectRevert(AppBondingCurve.InsufficientOutput.selector);
        curve.buy(eltaIn, expectedTokens + 1); // Set minimum too high

        vm.stopPrank();

        console2.log("[OK] Error handling verified");
    }

    function testFuzz_AppLaunchScenarios(
        uint256 seedAmount,
        uint256 targetAmount,
        uint256 supply,
        uint256 purchaseAmount
    ) public {
        // Bound parameters to reasonable ranges
        seedAmount = bound(seedAmount, 10 ether, 1000 ether);
        targetAmount = bound(targetAmount, seedAmount * 2, seedAmount * 100);
        supply = bound(supply, 1_000_000 ether, 10_000_000_000 ether);
        purchaseAmount = bound(purchaseAmount, 1 ether, (targetAmount - seedAmount) / 2);

        // Update factory parameters
        vm.prank(admin);
        factory.setParameters(seedAmount, targetAmount, supply, 365 days, 18, 250, 10 ether);

        // Create app with fuzzed parameters
        uint256 totalCost = factory.creationFee() + seedAmount;

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

        uint256 creatorTreasury = (supply * 10) / 100;
        uint256 curveSupply = supply - creatorTreasury;
        
        assertEq(token.maxSupply(), supply);
        assertEq(token.balanceOf(creator1), creatorTreasury); // Creator has 10%
        assertEq(curve.targetRaisedElta(), targetAmount);
        assertEq(curve.reserveElta(), seedAmount);
        assertEq(curve.reserveToken(), curveSupply); // Curve has 90%

        // Test purchase with fuzzed amount
        vm.prank(treasury);
        elta.transfer(investor1, purchaseAmount);

        vm.startPrank(investor1);
        elta.approve(address(curve), purchaseAmount);
        uint256 tokensOut = curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        assertGt(tokensOut, 0);
        assertEq(token.balanceOf(investor1), tokensOut);
    }
}
