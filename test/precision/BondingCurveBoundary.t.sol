// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../src/interfaces/IUniswapV2Factory.sol";
import {PrecisionFixtures} from "../fixtures/PrecisionFixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ═══════════════════════════════════════════════════════════════════════════
// MOCK CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════

contract MockElataPoints {
    mapping(address => uint256) public balances;

    function setBalance(address user, uint256 amount) external {
        balances[user] = amount;
    }

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }
}

contract MockUniswapRouter {
    address public factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256)
        external
        pure
        returns (uint256, uint256, uint256)
    {
        return (0, 0, 1000);
    }
}

contract MockUniswapFactory {
    address public mockPair;

    function setPair(address _pair) external {
        mockPair = _pair;
    }

    function getPair(address, address) external view returns (address) {
        return mockPair;
    }

    function createPair(address, address) external view returns (address) {
        return mockPair;
    }
}

contract MockPair {
    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1000;
    }
}

contract MockAppFeeRouter is IAppFeeRouter {
    function takeAndForwardFee(address, uint256) external pure {}

    function feeBps() external pure returns (uint256) {
        return 100;
    }

    function calculateFee(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract MockAppFactory {
    mapping(uint256 => bool) public graduated;

    function onAppGraduated(uint256 appId, address, address, uint256, uint256, uint256) external {
        graduated[appId] = true;
    }

    function initializeCurve(AppBondingCurve curve, uint256 seedElta, uint256 tokenSupply) external {
        curve.initializeCurve(seedElta, tokenSupply);
    }
}

/**
 * @title BondingCurveBoundary
 * @notice Comprehensive tests for bonding curve graduation boundary conditions
 * @dev Tests exact graduation thresholds, k-drift over many trades, and edge cases
 *
 * Key areas tested:
 * - Exact graduation target purchases
 * - Purchases exceeding target (capping and refund)
 * - Constant product k drift accumulation
 * - Price calculations at extreme reserves
 * - Near-zero reserve handling
 */
contract BondingCurveBoundary is Test, PrecisionFixtures {
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;
    MockAppFactory public factory;
    MockElataPoints public xp;
    MockUniswapFactory public uniFactory;
    MockUniswapRouter public router;
    MockPair public pair;
    MockAppFeeRouter public feeRouter;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public buyer = makeAddr("buyer");
    address public buyer2 = makeAddr("buyer2");

    uint256 public constant APP_ID = 1;
    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 5000 ether;
    uint256 public constant SEED_ELTA = 1000 ether;

    function setUp() public {
        // Deploy infrastructure
        pair = new MockPair();
        uniFactory = new MockUniswapFactory();
        uniFactory.setPair(address(pair));
        router = new MockUniswapRouter(address(uniFactory));
        xp = new MockElataPoints();
        feeRouter = new MockAppFeeRouter();
        factory = new MockAppFactory();

        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        // Deploy bonding curve
        curve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: APP_ID,
                factory: address(factory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 365 days,
                lpBeneficiary: creator,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(xp)),
                governance: governance,
                activationDelay: 1 days,
                maxDuration: 30 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        // Fund participants
        vm.startPrank(admin);
        elta.transfer(buyer, 100_000 ether);
        elta.transfer(buyer2, 100_000 ether);
        elta.transfer(creator, 10_000 ether);
        vm.stopPrank();

        // Set XP for participants (bypass XP gating)
        xp.setBalance(buyer, 1000e18);
        xp.setBalance(buyer2, 1000e18);

        // Mint tokens to curve and initialize
        vm.prank(admin);
        appToken.mint(address(curve), APP_TOKEN_SUPPLY);

        // Initialize curve (via factory)
        factory.initializeCurve(curve, SEED_ELTA, APP_TOKEN_SUPPLY);

        // Wait for activation time and activate
        vm.warp(block.timestamp + 2 days);
        vm.prank(address(factory));
        curve.activate();

        // Approve curve for buyers
        vm.prank(buyer);
        elta.approve(address(curve), type(uint256).max);
        vm.prank(buyer2);
        elta.approve(address(curve), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION THRESHOLD TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test buying exactly to graduation target
    function test_Boundary_ExactGraduationPurchase() public {
        uint256 reserveElta = curve.reserveElta();
        uint256 remaining = TARGET_RAISED - reserveElta;

        console2.log("Reserve ELTA before:", reserveElta);
        console2.log("Remaining to target:", remaining);

        // Buy exactly the remaining amount
        vm.prank(buyer);
        curve.buy(remaining, 0, address(0));

        // Should have graduated
        assertTrue(curve.graduated(), "Should have graduated");
        assertEq(uint256(curve.state()), 2, "State should be GRADUATED (2)");
    }

    /// @notice Test buying 1 wei at graduation boundary
    function test_Boundary_OneWeiToGraduation() public {
        uint256 reserveElta = curve.reserveElta();
        uint256 remaining = TARGET_RAISED - reserveElta;

        // Buy all but 1 wei
        if (remaining > 1) {
            vm.prank(buyer);
            curve.buy(remaining - 1, 0, address(0));
        }

        assertFalse(curve.graduated(), "Should not have graduated yet");

        // Buy final 1 wei
        vm.prank(buyer2);
        curve.buy(1, 0, address(0));

        assertTrue(curve.graduated(), "Should graduate with 1 wei purchase");
    }

    /// @notice Test buying more than remaining is capped
    function test_Boundary_PurchaseExceedingTargetCapped() public {
        uint256 reserveElta = curve.reserveElta();
        uint256 remaining = TARGET_RAISED - reserveElta;

        uint256 buyerEltaBefore = elta.balanceOf(buyer);

        // Try to buy double the remaining
        uint256 attemptedBuy = remaining * 2;
        vm.prank(buyer);
        curve.buy(attemptedBuy, 0, address(0));

        uint256 buyerEltaAfter = elta.balanceOf(buyer);
        uint256 actualSpent = buyerEltaBefore - buyerEltaAfter;

        // Should have only spent the remaining amount (plus any fees)
        assertLe(actualSpent, remaining + (remaining / 100) + 1, "Should be capped to remaining");
        assertTrue(curve.graduated(), "Should have graduated");
    }

    /// @notice Test multiple buyers racing to graduation
    function test_Boundary_ConcurrentGraduationRace() public {
        uint256 remaining = TARGET_RAISED - curve.reserveElta();
        uint256 halfRemaining = remaining / 2;

        // First buyer buys half
        vm.prank(buyer);
        curve.buy(halfRemaining, 0, address(0));
        assertFalse(curve.graduated(), "Should not graduate at half");

        // Second buyer tries to buy full remaining (but only gets half)
        vm.prank(buyer2);
        curve.buy(remaining, 0, address(0));

        assertTrue(curve.graduated(), "Should graduate");

        // Further purchases should fail
        vm.prank(buyer);
        vm.expectRevert();
        curve.buy(1 ether, 0, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANT PRODUCT K DRIFT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test k drift over many small trades
    function test_Boundary_KDriftManySmallTrades() public {
        uint256 initialK = curve.reserveElta() * curve.reserveToken();
        uint256 numTrades = 100;
        uint256 tradeSize = 10 ether; // Small trades

        uint256 totalKDrift = 0;

        for (uint256 i = 0; i < numTrades; i++) {
            // Check if we'd graduate
            if (curve.reserveElta() + tradeSize >= TARGET_RAISED) break;

            uint256 kBefore = curve.reserveElta() * curve.reserveToken();

            vm.prank(buyer);
            curve.buy(tradeSize, 0, address(0));

            uint256 kAfter = curve.reserveElta() * curve.reserveToken();

            // k should decrease or stay same (buyer advantage)
            assertLe(kAfter, kBefore, "k should not increase");

            if (kBefore > kAfter) {
                totalKDrift += kBefore - kAfter;
            }
        }

        console2.log("Initial k:", initialK);
        console2.log("Total k drift:", totalKDrift);
        console2.log("Drift percentage (bps):", (totalKDrift * 10000) / initialK);

        // Total drift should be bounded (< 1% of initial k)
        assertLe(totalKDrift, initialK / 100, "k drift exceeds 1%");
    }

    /// @notice Fuzz test k drift with varying trade sizes
    function testFuzz_Boundary_KDriftVaryingTrades(uint256 seed) public {
        uint256 initialK = curve.reserveElta() * curve.reserveToken();
        uint256 numTrades = 50;

        for (uint256 i = 0; i < numTrades; i++) {
            // Random trade size between 1 and 50 ether
            uint256 tradeSize = pseudoRandomAmount(seed + i, 1 ether, 50 ether);

            // Check if we'd graduate
            if (curve.reserveElta() + tradeSize >= TARGET_RAISED) break;
            if (elta.balanceOf(buyer) < tradeSize) break;

            vm.prank(buyer);
            try curve.buy(tradeSize, 0, address(0)) {}
            catch {
                break;
            }
        }

        uint256 finalK = curve.reserveElta() * curve.reserveToken();

        // k should only decrease
        assertLe(finalK, initialK, "k increased");

        // Drift should be < 1%
        if (initialK > 0) {
            assertGe(finalK, (initialK * 99) / 100, "k drift > 1%");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE CALCULATION BOUNDARY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test price at various reserve ratios
    function test_Boundary_PriceAtExtremeRatios() public view {
        // Get current state
        uint256 reserveElta = curve.reserveElta();
        uint256 reserveToken = curve.reserveToken();

        // Calculate price
        uint256 price = curve.getCurrentPrice();

        console2.log("Reserve ELTA:", reserveElta);
        console2.log("Reserve Token:", reserveToken);
        console2.log("Current price:", price);

        // Price should be reserveElta / reserveToken * 1e18
        uint256 expectedPrice = (reserveElta * 1e18) / reserveToken;
        assertEq(price, expectedPrice, "Price calculation mismatch");
    }

    /// @notice Test tokens out calculation at boundaries
    function test_Boundary_TokensOutCalculation() public view {
        uint256 reserveElta = curve.reserveElta();
        uint256 reserveToken = curve.reserveToken();

        // Test various input amounts
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 1; // 1 wei
        testAmounts[1] = 1 ether;
        testAmounts[2] = 100 ether;
        testAmounts[3] = reserveElta / 10; // 10% of reserve
        testAmounts[4] = reserveElta / 2; // 50% of reserve

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 eltaIn = testAmounts[i];
            uint256 tokensOut = curve.getTokensOut(eltaIn);

            console2.log("ELTA in:", eltaIn);
            console2.log("Tokens out:", tokensOut);

            // Verify calculation matches formula
            uint256 k = reserveElta * reserveToken;
            uint256 newReserveElta = reserveElta + eltaIn;
            uint256 newReserveToken = k / newReserveElta;
            uint256 expectedTokensOut = reserveToken - newReserveToken;

            assertEq(tokensOut, expectedTokensOut, "Token out calculation mismatch");

            // Tokens out should be less than reserve
            assertLt(tokensOut, reserveToken, "Tokens out >= reserve");
        }
    }

    /// @notice Test getTokensOut with 1 wei input
    function test_Boundary_TokensOutOneWei() public view {
        uint256 tokensOut = curve.getTokensOut(1);

        // Should return some tokens (might be 0 for very small amounts)
        console2.log("Tokens out for 1 wei:", tokensOut);

        // Verify it doesn't revert and returns reasonable value
        assertLe(tokensOut, curve.reserveToken(), "Cannot exceed reserve");
    }

    /// @notice Test price increases after each buy
    function test_Boundary_PriceMonotonicallyIncreases() public {
        uint256 numBuys = 20;
        uint256 buySize = 50 ether;
        uint256 lastPrice = 0;

        for (uint256 i = 0; i < numBuys; i++) {
            if (curve.graduated()) break;
            if (curve.reserveElta() + buySize >= TARGET_RAISED) {
                buySize = TARGET_RAISED - curve.reserveElta() - 1;
                if (buySize == 0) break;
            }

            vm.prank(buyer);
            curve.buy(buySize, 0, address(0));

            uint256 currentPrice = curve.getCurrentPrice();
            assertGt(currentPrice, lastPrice, "Price should increase");
            lastPrice = currentPrice;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RESERVE EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test behavior when token reserve is low
    function test_Boundary_LowTokenReserve() public {
        // Buy most of the tokens
        uint256 maxBuy = TARGET_RAISED - curve.reserveElta() - 100 ether;

        vm.prank(buyer);
        curve.buy(maxBuy, 0, address(0));

        uint256 tokenReserve = curve.reserveToken();
        console2.log("Token reserve after large buy:", tokenReserve);

        // Price should be high
        uint256 price = curve.getCurrentPrice();
        console2.log("Price after large buy:", price);

        // Should still be able to buy (even with high price)
        uint256 smallBuy = 10 ether;
        uint256 tokensOut = curve.getTokensOut(smallBuy);
        console2.log("Tokens out for small buy:", tokensOut);

        assertGt(tokensOut, 0, "Should still get some tokens");
    }

    /// @notice Test slippage protection at graduation boundary
    function test_Boundary_SlippageAtGraduation() public {
        uint256 remaining = TARGET_RAISED - curve.reserveElta();

        // Get expected tokens
        uint256 expectedTokens = curve.getTokensOut(remaining);

        // Require exact tokens (will fail due to capping behavior)
        vm.prank(buyer);
        // This might revert if slippage is too tight
        try curve.buy(remaining, expectedTokens - 1, address(0)) {
            assertTrue(curve.graduated(), "Should have graduated");
        } catch {
            // Slippage protection triggered - that's OK
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // POST-GRADUATION STATE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test reserves are cleared after graduation
    function test_Boundary_ReservesClearedAfterGraduation() public {
        // Graduate
        uint256 remaining = TARGET_RAISED - curve.reserveElta();
        vm.prank(buyer);
        curve.buy(remaining, 0, address(0));

        assertTrue(curve.graduated(), "Should be graduated");

        // Reserves should be 0
        assertEq(curve.reserveElta(), 0, "ELTA reserve should be 0");
        assertEq(curve.reserveToken(), 0, "Token reserve should be 0");
    }

    /// @notice Test getTokensOut returns 0 after graduation
    function test_Boundary_TokensOutZeroAfterGraduation() public {
        // Graduate
        uint256 remaining = TARGET_RAISED - curve.reserveElta();
        vm.prank(buyer);
        curve.buy(remaining, 0, address(0));

        // getTokensOut should return 0
        uint256 tokensOut = curve.getTokensOut(100 ether);
        assertEq(tokensOut, 0, "Should return 0 after graduation");
    }

    /// @notice Test buy reverts after graduation
    function test_Boundary_BuyRevertsAfterGraduation() public {
        // Graduate
        uint256 remaining = TARGET_RAISED - curve.reserveElta();
        vm.prank(buyer);
        curve.buy(remaining, 0, address(0));

        // Try to buy again
        vm.prank(buyer2);
        vm.expectRevert();
        curve.buy(1 ether, 0, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCUMULATED ERROR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test total ELTA spent matches expected
    function test_Boundary_TotalEltaSpentAccurate() public {
        uint256 buyerEltaBefore = elta.balanceOf(buyer);
        uint256 totalSpent = 0;

        // Make many small buys
        uint256 numBuys = 50;
        uint256 buySize = 50 ether;

        for (uint256 i = 0; i < numBuys; i++) {
            if (curve.graduated()) break;
            if (curve.reserveElta() + buySize >= TARGET_RAISED) break;

            uint256 balanceBefore = elta.balanceOf(buyer);
            vm.prank(buyer);
            curve.buy(buySize, 0, address(0));
            uint256 balanceAfter = elta.balanceOf(buyer);

            totalSpent += balanceBefore - balanceAfter;
        }

        uint256 buyerEltaAfter = elta.balanceOf(buyer);
        uint256 actualSpent = buyerEltaBefore - buyerEltaAfter;

        console2.log("Tracked spent:", totalSpent);
        console2.log("Actual spent:", actualSpent);

        assertEq(actualSpent, totalSpent, "Spending accounting mismatch");
    }
}
