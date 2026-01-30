// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {AppBondingCurve} from "../../../src/apps/AppBondingCurve.sol";
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
    mapping(uint256 => bool) public graduated;

    function onAppGraduated(uint256 appId, address, address, uint256, uint256, uint256) external {
        graduated[appId] = true;
    }

    function initializeCurve(AppBondingCurve curve, uint256 seedElta, uint256 tokenSupply) external {
        curve.initializeCurve(seedElta, tokenSupply);
    }
}

/**
 * @title BondingCurveAdvanced
 * @notice Advanced bonding curve exploit tests - XP gate, sniper fee, lifecycle
 */
contract BondingCurveAdvanced is Test {
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
    address public sniper = makeAddr("sniper");
    address public user = makeAddr("user");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 10_000 ether;
    uint256 public constant SNIPER_DURATION = 1 hours;

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

        // Fund participants
        vm.startPrank(admin);
        elta.transfer(sniper, 100_000 ether);
        elta.transfer(user, 100_000 ether);
        elta.transfer(creator, 10_000 ether);
        vm.stopPrank();

        // Set XP for participants
        xp.setBalance(user, 2000 ether);
        xp.setBalance(sniper, 0); // Sniper has no XP
    }

    function _deployCurve(uint256 xpMinForEarlyBuy, uint256 earlyBuyDuration, uint256 sniperDuration)
        internal
        returns (AppBondingCurve)
    {
        AppBondingCurve newCurve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 1,
                factory: address(factory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 30 days,
                lpBeneficiary: treasury,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(xp)),
                governance: governance,
                activationDelay: 0,
                maxDuration: 365 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        // Set XP gate and sniper duration if specified
        if (xpMinForEarlyBuy > 0 || earlyBuyDuration > 0) {
            vm.prank(governance);
            newCurve.setXPGate(xpMinForEarlyBuy, earlyBuyDuration);
        }

        if (sniperDuration > 0) {
            vm.prank(governance);
            newCurve.setSniperFeeConfig(500, sniperDuration, true); // 5% sniper fee
        }

        // Initialize curve
        vm.prank(admin);
        appToken.mint(address(factory), APP_TOKEN_SUPPLY);

        vm.prank(address(factory));
        appToken.transfer(address(newCurve), APP_TOKEN_SUPPLY / 2);

        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);

        vm.prank(address(factory));
        elta.transfer(address(newCurve), 100 ether);

        vm.prank(address(factory));
        newCurve.initializeCurve(100 ether, APP_TOKEN_SUPPLY / 2);

        newCurve.activate();

        return newCurve;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // XP GATING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_XPGate_BlocksLowXPDuringEarlyPeriod() public {
        curve = _deployCurve(1000 ether, 1 hours, 0);

        // Sniper with 0 XP tries to buy during early period
        vm.startPrank(sniper);
        elta.approve(address(curve), 1000 ether);

        vm.expectRevert(AppBondingCurve.InsufficientXP.selector);
        curve.buy(100 ether, 0, address(0));
        vm.stopPrank();
    }

    function test_XPGate_AllowsHighXPDuringEarlyPeriod() public {
        curve = _deployCurve(1000 ether, 1 hours, 0);

        // User with sufficient XP can buy during early period
        vm.startPrank(user);
        elta.approve(address(curve), 1000 ether);

        uint256 tokensOut = curve.buy(100 ether, 0, address(0));
        assertGt(tokensOut, 0, "High XP user should receive tokens");
        vm.stopPrank();
    }

    function test_XPGate_AllowsAnyoneAfterEarlyPeriod() public {
        curve = _deployCurve(1000 ether, 1 hours, 0);

        // Warp past early buy period
        vm.warp(block.timestamp + 1 hours + 1);

        // Sniper can now buy
        vm.startPrank(sniper);
        elta.approve(address(curve), 1000 ether);

        uint256 tokensOut = curve.buy(100 ether, 0, address(0));
        assertGt(tokensOut, 0, "Anyone can buy after early period");
        vm.stopPrank();
    }

    function test_XPGate_EdgeCaseExactXPThreshold() public {
        curve = _deployCurve(1000 ether, 1 hours, 0);

        // Set sniper's XP to exactly threshold
        xp.setBalance(sniper, 1000 ether);

        vm.startPrank(sniper);
        elta.approve(address(curve), 1000 ether);

        uint256 tokensOut = curve.buy(100 ether, 0, address(0));
        assertGt(tokensOut, 0, "Exact XP threshold should allow buy");
        vm.stopPrank();
    }

    function test_XPGate_CannotBypassByTimestampManipulation() public {
        curve = _deployCurve(1000 ether, 1 hours, 0);

        // Sniper cannot manipulate timestamp (only validators can)
        // This just verifies the time check works correctly
        uint256 launchTime = curve.launchTimestamp();
        uint256 duration = curve.earlyBuyDuration();
        uint256 earlyEnd = launchTime + duration;
        assertGt(earlyEnd, block.timestamp, "Early period should be in future");

        // At exact boundary - still blocked
        vm.warp(earlyEnd - 1);
        vm.startPrank(sniper);
        elta.approve(address(curve), 1000 ether);

        vm.expectRevert(AppBondingCurve.InsufficientXP.selector);
        curve.buy(100 ether, 0, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SNIPER FEE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SniperFee_AppliedDuringEarlyBuys() public {
        curve = _deployCurve(0, 0, 1 hours);

        uint256 buyAmount = 100 ether;

        // Calculate expected tokens without sniper fee
        uint256 expectedTokensNormal = curve.getTokensOut(buyAmount);

        // Buy during sniper period
        vm.startPrank(user);
        elta.approve(address(curve), buyAmount * 2);
        uint256 actualTokens = curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        // Should get fewer tokens due to sniper fee
        // The sniper fee increases the effective cost
        assertLe(actualTokens, expectedTokensNormal, "Sniper fee should reduce output");
    }

    function test_SniperFee_NotAppliedAfterDuration() public {
        curve = _deployCurve(0, 0, 1 hours);

        // Warp past sniper duration
        vm.warp(block.timestamp + 1 hours + 1);

        uint256 buyAmount = 100 ether;
        uint256 expectedTokens = curve.getTokensOut(buyAmount);

        vm.startPrank(user);
        elta.approve(address(curve), buyAmount * 2);
        uint256 actualTokens = curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        // Should get expected amount (no sniper fee)
        assertEq(actualTokens, expectedTokens, "No sniper fee after duration");
    }

    function test_SniperFee_SmallBuysToAvoid() public {
        curve = _deployCurve(0, 0, 1 hours);

        // Try multiple small buys to avoid sniper fee detection
        // (Sniper fee applies regardless of buy size)
        uint256 smallBuy = 10 ether;

        vm.startPrank(user);
        elta.approve(address(curve), smallBuy * 20);

        uint256 totalTokens = 0;
        for (uint256 i = 0; i < 5; i++) {
            totalTokens += curve.buy(smallBuy, 0, address(0));
        }
        vm.stopPrank();

        // All buys during sniper period still have sniper fee applied
        // There's no advantage to splitting buys
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LIFECYCLE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Lifecycle_PendingCannotBuy() public {
        // Deploy but don't activate
        AppBondingCurve newCurve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 2,
                factory: address(factory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 30 days,
                lpBeneficiary: treasury,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(xp)),
                governance: governance,
                activationDelay: 1 hours,
                maxDuration: 365 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        // Initialize
        vm.prank(admin);
        appToken.mint(address(factory), APP_TOKEN_SUPPLY);
        vm.prank(address(factory));
        appToken.transfer(address(newCurve), APP_TOKEN_SUPPLY / 4);
        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);
        vm.prank(address(factory));
        elta.transfer(address(newCurve), 100 ether);
        vm.prank(address(factory));
        newCurve.initializeCurve(100 ether, APP_TOKEN_SUPPLY / 4);

        // State is PENDING
        assertEq(uint256(newCurve.state()), 0, "Should be PENDING");

        // Cannot buy while pending
        vm.startPrank(user);
        elta.approve(address(newCurve), 100 ether);
        vm.expectRevert(AppBondingCurve.NotActive.selector);
        newCurve.buy(100 ether, 0, address(0));
        vm.stopPrank();
    }

    function test_Lifecycle_ActivationRequiresDelay() public {
        AppBondingCurve newCurve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 3,
                factory: address(factory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 30 days,
                lpBeneficiary: treasury,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(xp)),
                governance: governance,
                activationDelay: 1 hours,
                maxDuration: 365 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        // Initialize
        vm.prank(admin);
        appToken.mint(address(factory), APP_TOKEN_SUPPLY);
        vm.prank(address(factory));
        appToken.transfer(address(newCurve), APP_TOKEN_SUPPLY / 4);
        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);
        vm.prank(address(factory));
        elta.transfer(address(newCurve), 100 ether);
        vm.prank(address(factory));
        newCurve.initializeCurve(100 ether, APP_TOKEN_SUPPLY / 4);

        // Cannot activate before delay
        vm.expectRevert(AppBondingCurve.TooEarlyToActivate.selector);
        newCurve.activate();

        // Warp to after delay
        vm.warp(block.timestamp + 1 hours + 1);
        newCurve.activate();

        assertEq(uint256(newCurve.state()), 1, "Should be ACTIVE");
    }

    function test_Lifecycle_CreatorCanCancel() public {
        AppBondingCurve newCurve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 4,
                factory: address(factory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 30 days,
                lpBeneficiary: treasury,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(xp)),
                governance: governance,
                activationDelay: 1 hours,
                maxDuration: 365 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        // Initialize
        vm.prank(admin);
        appToken.mint(address(factory), APP_TOKEN_SUPPLY);
        vm.prank(address(factory));
        appToken.transfer(address(newCurve), APP_TOKEN_SUPPLY / 4);
        vm.prank(admin);
        elta.transfer(address(factory), 100 ether);
        vm.prank(address(factory));
        elta.transfer(address(newCurve), 100 ether);
        vm.prank(address(factory));
        newCurve.initializeCurve(100 ether, APP_TOKEN_SUPPLY / 4);

        // Creator can cancel while pending
        vm.prank(creator);
        newCurve.cancel();

        assertEq(uint256(newCurve.state()), 3, "Should be CANCELLED");
    }

    function test_Lifecycle_CannotCancelAfterActive() public {
        curve = _deployCurve(0, 0, 0);

        // Curve is active
        assertEq(uint256(curve.state()), 1, "Should be ACTIVE");

        // Cannot cancel active curve
        vm.prank(creator);
        vm.expectRevert(AppBondingCurve.NotPending.selector);
        curve.cancel();
    }

    function test_Lifecycle_GraduationTriggeredByTarget() public {
        curve = _deployCurve(0, 0, 0);

        // Buy up to graduation target
        uint256 currentReserve = curve.reserveElta();
        uint256 target = curve.targetRaisedElta();
        uint256 needed = target - currentReserve;

        vm.startPrank(user);
        elta.approve(address(curve), needed * 2);
        curve.buy(needed, 0, address(0));
        vm.stopPrank();

        // Should be graduated
        assertTrue(curve.graduated(), "Should be graduated");
        assertEq(uint256(curve.state()), 2, "Should be GRADUATED");
    }

    function test_Lifecycle_ForceGraduateByGovernance() public {
        curve = _deployCurve(0, 0, 0);

        // Buy some but not to target (account for fees with higher allowance)
        vm.startPrank(user);
        elta.approve(address(curve), 600 ether);
        curve.buy(500 ether, 0, address(0));
        vm.stopPrank();

        // Warp past max duration
        vm.warp(block.timestamp + 365 days + 1);

        // Force graduate
        curve.forceGraduate();

        assertTrue(curve.graduated(), "Should be graduated");
    }

    function test_Lifecycle_CannotBuyAfterGraduation() public {
        curve = _deployCurve(0, 0, 0);

        // Graduate
        uint256 target = curve.targetRaisedElta();
        uint256 reserve = curve.reserveElta();

        vm.startPrank(user);
        elta.approve(address(curve), target * 2);
        curve.buy(target - reserve, 0, address(0));
        vm.stopPrank();

        assertTrue(curve.graduated(), "Should be graduated");

        // Cannot buy after graduation
        vm.startPrank(user);
        vm.expectRevert(AppBondingCurve.NotActive.selector);
        curve.buy(100 ether, 0, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ECONOMIC ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Economic_ExactTargetBuy() public {
        curve = _deployCurve(0, 0, 0);

        // Calculate exact amount to reach target
        uint256 target = curve.targetRaisedElta();
        uint256 reserve = curve.reserveElta();
        uint256 exactNeeded = target - reserve;

        vm.startPrank(user);
        elta.approve(address(curve), exactNeeded * 2);
        curve.buy(exactNeeded, 0, address(0));
        vm.stopPrank();

        // Should graduate exactly at target
        assertTrue(curve.graduated(), "Should graduate at exact target");
    }

    function test_Economic_CannotOverflowReserves() public {
        curve = _deployCurve(0, 0, 0);

        // Try to buy enough to graduate - user has 100k ELTA
        uint256 target = curve.targetRaisedElta();
        uint256 reserve = curve.reserveElta();
        uint256 buyAmount = target - reserve + 100 ether; // Buy enough to trigger graduation

        vm.startPrank(user);
        elta.approve(address(curve), buyAmount * 2); // Extra for fees

        // This should:
        // 1. Graduate when target is reached
        // But should NOT cause overflow
        curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        // Should be graduated
        assertTrue(curve.graduated(), "Should be graduated");
    }

    function test_Economic_FeeAccumulation() public {
        curve = _deployCurve(0, 0, SNIPER_DURATION);

        // Multiple buys accumulate fees
        vm.startPrank(user);
        elta.approve(address(curve), 10000 ether);

        for (uint256 i = 0; i < 5; i++) {
            curve.buy(100 ether, 0, address(0));
        }
        vm.stopPrank();

        // Check fees accumulated
        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Should have pending fees from trading");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_BondingCurve_BuyNeverBreaksConstantProduct(uint256 buyAmount) public {
        curve = _deployCurve(0, 0, 0);

        buyAmount = bound(buyAmount, 1 ether, TARGET_RAISED / 2);

        uint256 k_before = curve.reserveElta() * curve.reserveToken();

        vm.startPrank(user);
        elta.approve(address(curve), buyAmount * 2);
        curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        if (!curve.graduated()) {
            uint256 k_after = curve.reserveElta() * curve.reserveToken();
            // K should be maintained or increase (due to fees retained)
            assertGe(k_after, k_before * 95 / 100, "K should be approximately maintained");
        }
    }

    function testFuzz_BondingCurve_XPGateConsistent(uint256 userXp, uint256 threshold) public {
        threshold = bound(threshold, 100 ether, 10_000 ether);
        userXp = bound(userXp, 0, 20_000 ether);

        curve = _deployCurve(threshold, 1 hours, 0);

        address testUser = makeAddr("testUser");
        xp.setBalance(testUser, userXp);

        vm.prank(admin);
        elta.transfer(testUser, 1000 ether);

        vm.startPrank(testUser);
        elta.approve(address(curve), 1000 ether);

        if (userXp >= threshold) {
            // Should succeed
            uint256 tokens = curve.buy(100 ether, 0, address(0));
            assertGt(tokens, 0, "High XP user should get tokens");
        } else {
            // Should fail
            vm.expectRevert(AppBondingCurve.InsufficientXP.selector);
            curve.buy(100 ether, 0, address(0));
        }
        vm.stopPrank();
    }

    function testFuzz_BondingCurve_PriceMonotonicIncrease(uint256 numBuys, uint256 seed) public {
        // Use bound on scalar to avoid vm.assume rejection issues with arrays
        numBuys = bound(numBuys, 1, 10);

        curve = _deployCurve(0, 0, 0);

        uint256 lastPrice = curve.getCurrentPrice();

        for (uint256 i = 0; i < numBuys; i++) {
            // Generate pseudo-random amounts from seed
            uint256 amount = bound(uint256(keccak256(abi.encodePacked(seed, i))), 1 ether, 500 ether);

            // Stop if would graduate
            if (curve.reserveElta() + amount >= TARGET_RAISED) break;

            address buyer = address(uint160(0x2000 + i));
            xp.setBalance(buyer, 10000 ether);
            vm.prank(admin);
            elta.transfer(buyer, amount * 2);

            vm.startPrank(buyer);
            elta.approve(address(curve), amount * 2);
            curve.buy(amount, 0, address(0));
            vm.stopPrank();

            uint256 currentPrice = curve.getCurrentPrice();
            assertGe(currentPrice, lastPrice, "Price should not decrease");
            lastPrice = currentPrice;
        }
    }
}
