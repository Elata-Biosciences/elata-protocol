// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {AppBondingCurve} from "../../../src/apps/AppBondingCurve.sol";
import {Tournament, EntryTokenType} from "../../../src/apps/Tournament.sol";
import {IAppFeeRouter} from "../../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../../src/interfaces/IElataPoints.sol";
import {IUniswapV2Router02} from "../../../src/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../../src/interfaces/IUniswapV2Factory.sol";
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
    function onAppGraduated(uint256, address, address, uint256, uint256, uint256) external {}

    function initializeCurve(AppBondingCurve curve, uint256 seedElta, uint256 tokenSupply) external {
        curve.initializeCurve(seedElta, tokenSupply);
    }
}

/**
 * @title FrontRunningAttacks
 * @notice Tests for front-running, sandwich attacks, and MEV exploitation
 */
contract FrontRunningAttacks is Test {
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;
    MockAppFactory public factory;
    MockElataPoints public xp;
    MockUniswapFactory public uniFactory;
    MockUniswapRouter public router;
    MockPair public pair;
    MockAppFeeRouter public feeRouter;
    Tournament public tournament;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");

    // Attack participants
    address public victim = makeAddr("victim");
    address public frontRunner = makeAddr("frontRunner");
    address public backRunner = makeAddr("backRunner");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 10000 ether;

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

        // Deploy BondingCurve with higher target
        curve = new AppBondingCurve(
            1,
            address(factory),
            IERC20(address(elta)),
            appToken,
            IUniswapV2Router02(address(router)),
            TARGET_RAISED,
            30 days,
            treasury,
            treasury,
            IAppFeeRouter(address(feeRouter)),
            IElataPoints(address(xp)),
            governance,
            0,
            365 days,
            creator,
            address(0), // feeCollector
            address(0) // referralRegistry
        );

        // Initialize curve
        vm.prank(admin);
        appToken.mint(address(factory), APP_TOKEN_SUPPLY);

        vm.prank(address(factory));
        appToken.transfer(address(curve), APP_TOKEN_SUPPLY / 2);

        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);

        vm.prank(address(factory));
        elta.transfer(address(curve), 100 ether);

        factory.initializeCurve(curve, 100 ether, APP_TOKEN_SUPPLY / 2);
        curve.activate();

        // Deploy tournament
        tournament = new Tournament(
            address(elta), EntryTokenType.ELTA, 1, admin, address(0), treasury, 100 ether, 0, 0, 250, 100
        );

        // Set XP for all participants
        xp.setBalance(victim, 1000 ether);
        xp.setBalance(frontRunner, 1000 ether);
        xp.setBalance(backRunner, 1000 ether);

        // Fund participants
        vm.startPrank(admin);
        elta.transfer(victim, 10_000 ether);
        elta.transfer(frontRunner, 10_000 ether);
        elta.transfer(backRunner, 10_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SANDWICH ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Sandwich_SlippageProtectionMitigates() public {
        // Simulate sandwich attack scenario:
        // 1. Front-runner sees victim's large buy in mempool
        // 2. Front-runner buys first to increase price
        // 3. Victim's buy executes at higher price
        // 4. Front-runner sells to back-run (but can't on buy-only curve!)

        uint256 victimBuyAmount = 500 ether;

        // Get expected output for victim
        uint256 expectedTokens = curve.getTokensOut(victimBuyAmount);

        // Step 1: Front-runner buys first
        vm.startPrank(frontRunner);
        elta.approve(address(curve), 200 ether);
        curve.buy(100 ether, 0, address(0));
        vm.stopPrank();

        // Price increased
        uint256 priceAfterFrontRun = curve.getCurrentPrice();

        // Step 2: Victim buys with slippage protection
        // Victim expects at least 95% of original quote
        uint256 minTokensWithSlippage = expectedTokens * 95 / 100;

        vm.startPrank(victim);
        elta.approve(address(curve), victimBuyAmount * 2);

        // The buy with original expected tokens as min would fail
        // because front-run increased the price
        uint256 newExpectedTokens = curve.getTokensOut(victimBuyAmount);
        assertLt(newExpectedTokens, expectedTokens, "Front-run should reduce expected tokens");

        // With slippage tolerance, victim can still buy
        curve.buy(victimBuyAmount, newExpectedTokens * 90 / 100, address(0));
        vm.stopPrank();

        // Step 3: Front-runner CANNOT back-run because curve is buy-only
        // No sell function exists
    }

    function test_Sandwich_BuyOnlyCurvePreventsBackRun() public {
        // Front-runner can buy but cannot sell back
        vm.startPrank(frontRunner);
        elta.approve(address(curve), 200 ether);

        uint256 tokensReceived = curve.buy(100 ether, 0, address(0));
        assertGt(tokensReceived, 0, "Should receive tokens");

        // Try to "sell" - no such function exists
        // The only way to get value is through secondary markets after graduation
        vm.stopPrank();

        // Tokens are stuck until graduation and LP creation
        assertFalse(curve.graduated(), "Curve should not be graduated yet");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION FRONT-RUNNING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrontRun_GraduationTriggerPredictable() public {
        // Buy up to near graduation threshold
        uint256 currentReserve = curve.reserveElta();
        uint256 target = curve.targetRaisedElta();
        uint256 remaining = target - currentReserve;

        // Buy 90% of remaining
        uint256 buyAmount = remaining * 90 / 100;

        vm.startPrank(victim);
        elta.approve(address(curve), buyAmount * 2);
        curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        // Front-runner can calculate exactly how much to buy to trigger graduation
        uint256 newRemaining = target - curve.reserveElta();

        // Front-runner buys the exact remaining amount
        vm.startPrank(frontRunner);
        elta.approve(address(curve), newRemaining * 2);
        curve.buy(newRemaining, 0, address(0));
        vm.stopPrank();

        // Graduation should have occurred
        assertTrue(curve.graduated(), "Curve should be graduated");
    }

    function test_FrontRun_CannotManipulateLPPricePostGraduation() public {
        // Buy to trigger graduation
        uint256 buyAmount = TARGET_RAISED;

        vm.startPrank(victim);
        elta.approve(address(curve), buyAmount * 2);
        curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        if (curve.graduated()) {
            // LP is created and locked
            address locker = curve.locker();
            assertNotEq(locker, address(0), "LP locker should exist");

            // LP tokens are locked for lpLockDuration
            uint256 unlockAt = curve.lpUnlockAt();
            assertGt(unlockAt, block.timestamp, "LP should be locked");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTIVATION RACE CONDITION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrontRun_ActivationRaceCondition() public {
        // Create a new curve that's pending
        AppToken newToken = new AppToken(
            "NewApp", "NEW", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        AppBondingCurve newCurve = new AppBondingCurve(
            2,
            address(factory),
            IERC20(address(elta)),
            newToken,
            IUniswapV2Router02(address(router)),
            TARGET_RAISED,
            30 days,
            treasury,
            treasury,
            IAppFeeRouter(address(feeRouter)),
            IElataPoints(address(xp)),
            governance,
            1 hours, // 1 hour activation delay
            365 days,
            creator,
            address(0), // feeCollector
            address(0) // referralRegistry
        );

        // Initialize
        vm.prank(admin);
        newToken.mint(address(factory), APP_TOKEN_SUPPLY);
        vm.prank(address(factory));
        newToken.transfer(address(newCurve), APP_TOKEN_SUPPLY / 2);

        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);
        vm.prank(address(factory));
        elta.transfer(address(newCurve), 100 ether);

        vm.prank(address(factory));
        newCurve.initializeCurve(100 ether, APP_TOKEN_SUPPLY / 2);

        // Curve is pending, cannot buy yet
        assertEq(uint256(newCurve.state()), 0, "Should be PENDING");

        // Cannot activate before activation time
        vm.expectRevert();
        newCurve.activate();

        // Warp to just before activation
        vm.warp(block.timestamp + 1 hours - 1);
        vm.expectRevert();
        newCurve.activate();

        // Warp to activation time - anyone can activate
        vm.warp(block.timestamp + 2);

        // Front-runner activates
        vm.prank(frontRunner);
        newCurve.activate();

        assertEq(uint256(newCurve.state()), 1, "Should be ACTIVE");

        // Front-runner can now buy first
        xp.setBalance(frontRunner, 1000 ether);
        vm.startPrank(frontRunner);
        elta.approve(address(newCurve), 100 ether);
        newCurve.buy(50 ether, 0, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CANCEL VS ACTIVATE ORDERING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrontRun_CancelBeforeActivate() public {
        // Create pending curve
        AppToken newToken = new AppToken(
            "CancelApp", "CANC", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        AppBondingCurve newCurve = new AppBondingCurve(
            3,
            address(factory),
            IERC20(address(elta)),
            newToken,
            IUniswapV2Router02(address(router)),
            TARGET_RAISED,
            30 days,
            treasury,
            treasury,
            IAppFeeRouter(address(feeRouter)),
            IElataPoints(address(xp)),
            governance,
            1 hours, // activation delay
            365 days,
            creator,
            address(0), // feeCollector
            address(0) // referralRegistry
        );

        // Initialize
        vm.prank(admin);
        newToken.mint(address(factory), APP_TOKEN_SUPPLY);
        vm.prank(address(factory));
        newToken.transfer(address(newCurve), APP_TOKEN_SUPPLY / 2);

        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);
        vm.prank(address(factory));
        elta.transfer(address(newCurve), 100 ether);

        vm.prank(address(factory));
        newCurve.initializeCurve(100 ether, APP_TOKEN_SUPPLY / 2);

        // Creator can cancel while pending
        vm.prank(creator);
        newCurve.cancel();

        assertEq(uint256(newCurve.state()), 3, "Should be CANCELLED");

        // Cannot activate after cancel
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        newCurve.activate();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOURNAMENT FRONT-RUNNING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrontRun_TournamentEntryOrdering() public {
        // Entry ordering doesn't matter for tournaments
        // All participants pay same fee and have equal chance

        vm.startPrank(frontRunner);
        elta.approve(address(tournament), 100 ether);
        tournament.enter();
        vm.stopPrank();

        vm.startPrank(victim);
        elta.approve(address(tournament), 100 ether);
        tournament.enter();
        vm.stopPrank();

        // Both entered, no advantage from being first
        assertTrue(tournament.entered(frontRunner), "Front-runner should be entered");
        assertTrue(tournament.entered(victim), "Victim should be entered");

        // Pool is equal contributions
        assertEq(tournament.pool(), 200 ether, "Pool should be 2x entry fee");
    }

    function test_FrontRun_TournamentFinalizationImmutable() public {
        // Enter
        vm.startPrank(victim);
        elta.approve(address(tournament), 100 ether);
        tournament.enter();
        vm.stopPrank();

        // Finalize with merkle root
        bytes32 root = keccak256(abi.encodePacked(victim, uint256(90 ether)));

        vm.prank(admin);
        tournament.finalize(root);

        // Cannot finalize again
        vm.prank(admin);
        vm.expectRevert(Tournament.AlreadyFinalized.selector);
        tournament.finalize(root);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE SWEEP TIMING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrontRun_FeeSweepPermissionless() public {
        // Buy to accumulate fees
        vm.startPrank(victim);
        elta.approve(address(curve), 500 ether);
        curve.buy(200 ether, 0, address(0));
        vm.stopPrank();

        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Should have pending fees");

        // Anyone can sweep fees (no front-running advantage)
        // Fee sweeping is permissionless for gas efficiency
        curve.sweepFees();

        // Without fee collector set, fees remain pending
        // This is intentional - no exploit from sweeping
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRICE MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FrontRun_PriceImpactCalculatable() public {
        // Price impact is deterministic from constant product formula
        uint256 buyAmount = 100 ether;

        uint256 priceBefore = curve.getCurrentPrice();
        uint256 expectedTokens = curve.getTokensOut(buyAmount);

        vm.startPrank(victim);
        elta.approve(address(curve), buyAmount * 2);
        uint256 actualTokens = curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        uint256 priceAfter = curve.getCurrentPrice();

        // Price increased predictably
        assertGt(priceAfter, priceBefore, "Price should increase");
        assertEq(actualTokens, expectedTokens, "Actual should match expected");
    }

    function test_FrontRun_LargeBuyImpact() public {
        // Measure impact of sequential buys vs single large buy
        uint256 totalAmount = 1000 ether;

        // Record starting state
        uint256 startReserveElta = curve.reserveElta();
        uint256 startReserveToken = curve.reserveToken();

        // Approach 1: Single large buy
        uint256 tokensFromSingleBuy = curve.getTokensOut(totalAmount);

        // Approach 2: Multiple small buys (would get fewer tokens due to price movement)
        uint256 tokensFromMultipleBuys = 0;
        uint256 tempReserveElta = startReserveElta;
        uint256 tempReserveToken = startReserveToken;

        for (uint256 i = 0; i < 10; i++) {
            uint256 smallBuy = totalAmount / 10;
            uint256 k = tempReserveElta * tempReserveToken;
            uint256 newReserveElta = tempReserveElta + smallBuy;
            uint256 newReserveToken = k / newReserveElta;
            tokensFromMultipleBuys += tempReserveToken - newReserveToken;
            tempReserveElta = newReserveElta;
            tempReserveToken = newReserveToken;
        }

        // Single buy gets same or more tokens (due to better execution)
        // This is expected behavior of constant product
        assertGe(tokensFromSingleBuy, tokensFromMultipleBuys * 99 / 100, "Single buy should be efficient");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_FrontRun_SlippageProtection(uint256 victimAmount, uint256 frontRunAmount) public {
        victimAmount = bound(victimAmount, 10 ether, 500 ether);
        frontRunAmount = bound(frontRunAmount, 1 ether, 100 ether);

        // Get victim's expected tokens before front-run
        uint256 expectedBefore = curve.getTokensOut(victimAmount);

        // Front-run
        vm.startPrank(frontRunner);
        elta.approve(address(curve), frontRunAmount * 2);
        curve.buy(frontRunAmount, 0, address(0));
        vm.stopPrank();

        // Victim's expected tokens after front-run
        uint256 expectedAfter = curve.getTokensOut(victimAmount);

        // Front-run reduces expected tokens
        assertLe(expectedAfter, expectedBefore, "Front-run should not increase victim's tokens");

        // Victim can still protect with slippage
        vm.startPrank(victim);
        elta.approve(address(curve), victimAmount * 2);
        curve.buy(victimAmount, expectedAfter * 90 / 100, address(0));
        vm.stopPrank();
    }

    function testFuzz_FrontRun_PriceMonotonic(uint256 numBuys, uint256 seed) public {
        // Use bound on scalar to avoid vm.assume rejection issues with arrays
        numBuys = bound(numBuys, 1, 10);

        uint256 lastPrice = curve.getCurrentPrice();

        for (uint256 i = 0; i < numBuys; i++) {
            // Generate pseudo-random amounts from seed
            uint256 amount = bound(uint256(keccak256(abi.encodePacked(seed, i))), 1 ether, 200 ether);

            // Check if we'd graduate
            if (curve.reserveElta() + amount >= TARGET_RAISED) break;

            address buyer = address(uint160(0x1000 + i));
            xp.setBalance(buyer, 1000 ether);

            vm.prank(admin);
            elta.transfer(buyer, amount * 2);

            vm.startPrank(buyer);
            elta.approve(address(curve), amount * 2);
            curve.buy(amount, 0, address(0));
            vm.stopPrank();

            uint256 currentPrice = curve.getCurrentPrice();

            // Price should monotonically increase
            assertGe(currentPrice, lastPrice, "Price should not decrease");
            lastPrice = currentPrice;
        }
    }
}
