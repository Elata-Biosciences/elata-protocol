// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {AppFactory} from "../../src/apps/AppFactory.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IRewardsDistributor} from "../../src/interfaces/IRewardsDistributor.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {ELTA} from "elta/ELTA.sol";
import {
    MockAppFeeRouter,
    MockAppRewardsDistributor,
    MockElataPoints,
    MockRewardsDistributor
} from "../mocks/MockContracts.sol";
import "forge-std/Test.sol";

/**
 * @title Concurrent Trading Integration Test
 * @notice Tests multi-user trading scenarios on bonding curves
 * @dev Simulates realistic trading with 10-20 users:
 *      - Concurrent buys in same block
 *      - Slippage protection validation
 *      - Fee accumulation accuracy
 *      - No state corruption under load
 */
contract ConcurrentTradingTest is Test {
    ELTA public elta;
    AppFactory public factory;
    MockElataPoints public mockXP;
    AppRegistry public registry;
    ContributorSplitFactory public splitFactory;
    FeeSwapper public feeSwapper;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public governance = makeAddr("governance");
    address public creator = makeAddr("creator");

    // 20 users for concurrent trading simulation
    address[20] public users;

    // Mock Uniswap
    address public mockRouter = makeAddr("mockRouter");
    address public mockUniFactory = makeAddr("mockUniFactory");

    uint256 public constant NUM_USERS = 20;
    uint256 public constant SEED_ELTA = 100 ether;
    uint256 public constant TARGET_RAISED = 42_000 ether;

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA(treasury);

        // Setup mock Uniswap
        vm.mockCall(mockRouter, abi.encodeWithSignature("factory()"), abi.encode(mockUniFactory));
        vm.mockCall(mockUniFactory, abi.encodeWithSignature("getPair(address,address)"), abi.encode(address(0)));

        // Deploy mocks
        MockAppFeeRouter mockFeeRouter = new MockAppFeeRouter();
        MockAppRewardsDistributor mockAppRewards = new MockAppRewardsDistributor();
        MockRewardsDistributor mockRewards = new MockRewardsDistributor();
        mockXP = new MockElataPoints();

        // Deploy factory
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

        // Setup users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));

            // Give each user ELTA and XP
            vm.prank(treasury);
            elta.transfer(users[i], 5_000 ether);
            mockXP.setBalance(users[i], 1000 ether);
        }

        // Setup creator
        vm.prank(treasury);
        elta.transfer(creator, 1_000 ether);
        mockXP.setBalance(creator, 1000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONCURRENT TRADING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MultipleBuyersInSameBlock() public {
        // Create and activate app
        uint256 appId = _createAndActivateApp();
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Record initial state
        (uint256 initialEltaReserve, uint256 initialTokenReserve,,,,) = curve.getCurveState();

        // All users buy in the same block
        uint256 totalEltaSpent = 0;
        uint256 totalTokensReceived = 0;

        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 buyAmount = 100 ether + (i * 10 ether); // Varying amounts

            vm.startPrank(users[i]);
            elta.approve(address(curve), buyAmount * 102 / 100);
            uint256 tokensOut = curve.buy(buyAmount, 0, address(0));
            vm.stopPrank();

            totalEltaSpent += buyAmount;
            totalTokensReceived += tokensOut;

            // Verify user received tokens
            assertEq(token.balanceOf(users[i]), tokensOut, "User token balance mismatch");
        }

        // Verify final state consistency
        (uint256 finalEltaReserve, uint256 finalTokenReserve,,,,) = curve.getCurveState();

        // ELTA reserve should have increased by total spent
        assertEq(finalEltaReserve, initialEltaReserve + totalEltaSpent, "ELTA reserve mismatch");

        // Token reserve should have decreased by total received
        assertEq(finalTokenReserve, initialTokenReserve - totalTokensReceived, "Token reserve mismatch");

        // Conservation check: tokens distributed + reserve = initial supply
        uint256 curveSupply = factory.defaultSupply() / 2;
        assertEq(totalTokensReceived + finalTokenReserve, curveSupply, "Token conservation violated");

        console2.log("Users traded:", NUM_USERS);
        console2.log("Total ELTA spent:", totalEltaSpent / 1e18);
        console2.log("Total tokens received:", totalTokensReceived / 1e18);
    }

    function test_SlippageProtectionUnderLoad() public {
        uint256 appId = _createAndActivateApp();
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // First user buys and sets a baseline price
        vm.startPrank(users[0]);
        elta.approve(address(curve), 1000 ether);
        curve.buy(500 ether, 0, address(0));
        vm.stopPrank();

        // Second user queries expected tokens
        uint256 expectedTokens = curve.getTokensOut(200 ether);

        // Third user frontrunns with a large purchase
        vm.startPrank(users[2]);
        elta.approve(address(curve), 2000 ether);
        curve.buy(1000 ether, 0, address(0));
        vm.stopPrank();

        // Second user's transaction should fail with original minTokensOut
        vm.startPrank(users[1]);
        elta.approve(address(curve), 500 ether);

        // This should revert because price moved
        vm.expectRevert(AppBondingCurve.InsufficientOutput.selector);
        curve.buy(200 ether, expectedTokens, address(0));

        // But with realistic slippage tolerance (5%), it should work
        uint256 newExpected = curve.getTokensOut(200 ether);
        curve.buy(200 ether, newExpected * 95 / 100, address(0));
        vm.stopPrank();
    }

    function test_FeeAccumulationWithManyTrades() public {
        uint256 appId = _createAndActivateApp();
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 initialPendingFees = curve.pendingFees();

        // Execute many small trades
        uint256 totalTradeVolume = 0;
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 buyAmount = 50 ether;

            vm.startPrank(users[i]);
            elta.approve(address(curve), buyAmount * 102 / 100);
            curve.buy(buyAmount, 0, address(0));
            vm.stopPrank();

            totalTradeVolume += buyAmount;
        }

        // Verify fees accumulated correctly (1% fee rate)
        uint256 finalPendingFees = curve.pendingFees();
        uint256 expectedFees = totalTradeVolume / 100; // 1% fee

        // Allow small rounding difference
        assertApproxEqAbs(finalPendingFees - initialPendingFees, expectedFees, NUM_USERS, "Fee accumulation inaccurate");

        console2.log("Total trade volume:", totalTradeVolume / 1e18, "ELTA");
        console2.log("Fees accumulated:", (finalPendingFees - initialPendingFees) / 1e18, "ELTA");
    }

    function test_NoStateCorruptionUnderLoad() public {
        uint256 appId = _createAndActivateApp();
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Track all state changes
        uint256 totalTokensDistributed = 0;
        uint256 totalEltaDeposited = 0;

        // Simulate chaotic trading: different amounts, different users, multiple rounds
        for (uint256 round = 0; round < 5; round++) {
            for (uint256 i = 0; i < NUM_USERS; i++) {
                // Skip some users randomly based on round
                if ((i + round) % 3 == 0) continue;

                uint256 buyAmount = 20 ether + (i * 5 ether) + (round * 10 ether);

                // Check if user has enough balance
                if (elta.balanceOf(users[i]) < buyAmount * 102 / 100) continue;

                vm.startPrank(users[i]);
                elta.approve(address(curve), buyAmount * 102 / 100);
                uint256 tokensOut = curve.buy(buyAmount, 0, address(0));
                vm.stopPrank();

                totalTokensDistributed += tokensOut;
                totalEltaDeposited += buyAmount;
            }
        }

        // Verify state consistency
        (uint256 eltaReserve, uint256 tokenReserve,,,,) = curve.getCurveState();

        // ELTA reserve = seed + deposits
        assertEq(eltaReserve, SEED_ELTA + totalEltaDeposited, "ELTA reserve corrupted");

        // Token reserve + distributed = initial curve supply
        uint256 curveSupply = factory.defaultSupply() / 2;
        assertEq(tokenReserve + totalTokensDistributed, curveSupply, "Token state corrupted");

        // Verify each user's balance is correctly tracked
        uint256 totalUserBalances = 0;
        for (uint256 i = 0; i < NUM_USERS; i++) {
            totalUserBalances += token.balanceOf(users[i]);
        }
        assertEq(totalUserBalances, totalTokensDistributed, "User balance tracking corrupted");

        console2.log("Rounds executed: 5");
        console2.log("Total ELTA deposited:", totalEltaDeposited / 1e18);
        console2.log("Total tokens distributed:", totalTokensDistributed / 1e18);
        console2.log("State integrity: VERIFIED");
    }

    function test_PriceImpactWithLargeTrades() public {
        uint256 appId = _createAndActivateApp();
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 initialPrice = curve.getCurrentPrice();

        // Execute a series of increasing trades to see price impact
        uint256[] memory prices = new uint256[](10);
        prices[0] = initialPrice;

        for (uint256 i = 0; i < 10; i++) {
            uint256 buyAmount = 500 ether;

            vm.startPrank(users[i]);
            elta.approve(address(curve), buyAmount * 102 / 100);
            curve.buy(buyAmount, 0, address(0));
            vm.stopPrank();

            if (i < 9) {
                prices[i + 1] = curve.getCurrentPrice();
            }
        }

        uint256 finalPrice = curve.getCurrentPrice();

        // Price should have increased monotonically
        for (uint256 i = 1; i < 10; i++) {
            assertGt(prices[i], prices[i - 1], "Price should increase with buys");
        }

        // Final price should be significantly higher than initial
        assertGt(finalPrice, initialPrice * 2, "Price impact too low");

        console2.log("Initial price:", initialPrice);
        console2.log("Final price:", finalPrice);
        console2.log("Price increase:", (finalPrice - initialPrice) * 100 / initialPrice, "%");
    }

    function test_ConcurrentBuysOnMultipleCurves() public {
        // Create multiple apps
        uint256 appId1 = _createAndActivateApp();
        uint256 appId2 = _createAndActivateAppForCreator(makeAddr("creator2"), "App2", "APP2");
        uint256 appId3 = _createAndActivateAppForCreator(makeAddr("creator3"), "App3", "APP3");

        AppFactory.App memory app1 = factory.getApp(appId1);
        AppFactory.App memory app2 = factory.getApp(appId2);
        AppFactory.App memory app3 = factory.getApp(appId3);

        AppBondingCurve curve1 = AppBondingCurve(app1.curve);
        AppBondingCurve curve2 = AppBondingCurve(app2.curve);
        AppBondingCurve curve3 = AppBondingCurve(app3.curve);

        // Users trade on different curves concurrently
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 buyAmount = 100 ether;

            // Each user picks a curve based on their index
            AppBondingCurve targetCurve;
            if (i % 3 == 0) targetCurve = curve1;
            else if (i % 3 == 1) targetCurve = curve2;
            else targetCurve = curve3;

            vm.startPrank(users[i]);
            elta.approve(address(targetCurve), buyAmount * 102 / 100);
            targetCurve.buy(buyAmount, 0, address(0));
            vm.stopPrank();
        }

        // Verify each curve maintained independent state
        (uint256 reserve1,,,,,) = curve1.getCurveState();
        (uint256 reserve2,,,,,) = curve2.getCurveState();
        (uint256 reserve3,,,,,) = curve3.getCurveState();

        // All should have grown but by different amounts based on trade distribution
        assertGt(reserve1, SEED_ELTA, "Curve 1 should have trades");
        assertGt(reserve2, SEED_ELTA, "Curve 2 should have trades");
        assertGt(reserve3, SEED_ELTA, "Curve 3 should have trades");

        console2.log("Curve 1 reserve:", reserve1 / 1e18, "ELTA");
        console2.log("Curve 2 reserve:", reserve2 / 1e18, "ELTA");
        console2.log("Curve 3 reserve:", reserve3 / 1e18, "ELTA");
    }

    function testFuzz_ConcurrentTradingStress(uint256 numTradesSeed, uint256 baseBuyAmountSeed) public {
        // Bound parameters
        uint256 numTrades = bound(numTradesSeed, 1, 20); // Limit to available users
        uint256 baseBuyAmount = bound(baseBuyAmountSeed, 1 ether, 50 ether);

        uint256 appId = _createAndActivateApp();
        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < numTrades; i++) {
            uint256 userIdx = i % NUM_USERS;
            uint256 buyAmount = baseBuyAmount + (i * 1 ether);

            // Calculate required amount with fee buffer
            uint256 requiredAmount = buyAmount + (buyAmount / 50); // 2% buffer

            // Skip if user doesn't have enough
            if (elta.balanceOf(users[userIdx]) < requiredAmount) continue;

            vm.startPrank(users[userIdx]);
            elta.approve(address(curve), requiredAmount);
            curve.buy(buyAmount, 0, address(0));
            vm.stopPrank();

            totalDeposited += buyAmount;
        }

        // Verify state consistency
        (uint256 eltaReserve,,,,,) = curve.getCurveState();
        assertEq(eltaReserve, SEED_ELTA + totalDeposited, "State inconsistency after fuzz");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _createAndActivateApp() internal returns (uint256 appId) {
        return _createAndActivateAppForCreator(creator, "TestApp", "TEST");
    }

    function _createAndActivateAppForCreator(address _creator, string memory name, string memory symbol)
        internal
        returns (uint256 appId)
    {
        // Fund creator if needed
        if (elta.balanceOf(_creator) < 200 ether) {
            vm.prank(treasury);
            elta.transfer(_creator, 200 ether);
            mockXP.setBalance(_creator, 1000 ether);
        }

        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(_creator);
        elta.approve(address(factory), totalCost);
        appId = factory.createApp(name, symbol, 0, "", "", "", new address[](0));
        vm.stopPrank();

        // Activate curve
        AppFactory.App memory app = factory.getApp(appId);
        vm.warp(block.timestamp + 1 hours + 1);
        AppBondingCurve(app.curve).activate();

        return appId;
    }
}
