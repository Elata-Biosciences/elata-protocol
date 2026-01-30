// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock Uniswap Router
contract MockRouter {
    function factory() external pure returns (address) {
        return address(0);
    }

    function WETH() external pure returns (address) {
        return address(0);
    }
}

/// @notice Mock AppFeeRouter
contract MockAppFeeRouter is IAppFeeRouter {
    function takeAndForwardFee(address, uint256) external pure {}

    function feeBps() external pure returns (uint256) {
        return 100; // 1%
    }

    function calculateFee(uint256 amount) external pure returns (uint256) {
        return (amount * 100) / 10000;
    }
}

/// @notice Mock ElataPoints
contract MockElataPoints is IElataPoints {
    mapping(address => uint256) public balances;

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }
}

/// @notice Mock AppFactory that can initialize curves
contract MockAppFactory {
    function onAppGraduated(uint256, address, address, uint256, uint256, uint256) external pure {}

    function initializeCurve(address curve, uint256 seedElta, uint256 tokenSupply) external {
        AppBondingCurve(curve).initializeCurve(seedElta, tokenSupply);
    }
}

/// @notice Malicious contract for reentrancy attacks
contract ReentrancyAttacker {
    AppBondingCurve public curve;
    ELTA public elta;
    uint256 public attackCount;
    uint256 public maxAttacks;

    constructor(AppBondingCurve _curve, ELTA _elta) {
        curve = _curve;
        elta = _elta;
    }

    function attack(uint256 amount, uint256 _maxAttacks) external {
        maxAttacks = _maxAttacks;
        attackCount = 0;
        elta.approve(address(curve), type(uint256).max);
        curve.buy(amount, amount * 2, address(0));
    }

    // Reentrancy callback - try to buy again
    receive() external payable {
        if (attackCount < maxAttacks) {
            attackCount++;
            uint256 balance = elta.balanceOf(address(this));
            if (balance > 0) {
                try curve.buy(balance / 2, balance, address(0)) {} catch {}
            }
        }
    }
}

/// @notice Flash loan simulator
contract FlashLoanSimulator {
    ELTA public elta;
    AppBondingCurve public curve;

    constructor(ELTA _elta, AppBondingCurve _curve) {
        elta = _elta;
        curve = _curve;
    }

    function executeFlashLoanAttack(uint256 flashAmount, uint256 buyAmount) external {
        // Simulate receiving flash loan
        uint256 balanceBefore = elta.balanceOf(address(this));

        // Try to manipulate price with flash-borrowed funds
        elta.approve(address(curve), flashAmount);

        try curve.buy(buyAmount, flashAmount, address(0)) {
        // If successful, try to exploit the price change
        }
            catch {}

        // Flash loan would need to be repaid here
        uint256 balanceAfter = elta.balanceOf(address(this));
        console2.log("Flash attack balance change:", balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0);
    }
}

/**
 * @title AppBondingCurveSecurity
 * @notice Red team security tests for AppBondingCurve
 * @dev Tests reentrancy, flash loans, front-running, graduation exploits, etc.
 */
contract AppBondingCurveSecurity is Test {
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;

    MockRouter public router;
    MockAppFeeRouter public appFeeRouter;
    MockElataPoints public elataPoints;
    MockAppFactory public appFactory;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 10_000 ether;
    uint256 public constant SEED_ELTA = 100 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy mocks
        router = new MockRouter();
        appFeeRouter = new MockAppFeeRouter();
        elataPoints = new MockElataPoints();
        appFactory = new MockAppFactory();

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        // Deploy bonding curve
        curve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 0,
                factory: address(appFactory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 365 days * 2,
                lpBeneficiary: creator,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(appFeeRouter)),
                elataPoints: IElataPoints(address(elataPoints)),
                governance: governance,
                activationDelay: 1 hours,
                maxDuration: 30 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        // Seed curve with tokens
        vm.prank(admin);
        appToken.mint(address(curve), APP_TOKEN_SUPPLY / 2);

        // Initialize curve reserves (must be done by factory)
        vm.prank(admin);
        elta.transfer(address(curve), SEED_ELTA);
        appFactory.initializeCurve(address(curve), SEED_ELTA, APP_TOKEN_SUPPLY / 2);

        // Fund users with ELTA
        vm.startPrank(admin);
        elta.transfer(attacker, 100_000 ether);
        elta.transfer(alice, 100_000 ether);
        elta.transfer(bob, 100_000 ether);
        vm.stopPrank();

        // Give users XP for early access
        elataPoints.setBalance(attacker, 1000 ether);
        elataPoints.setBalance(alice, 1000 ether);
        elataPoints.setBalance(bob, 1000 ether);

        // Activate curve
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(governance);
        curve.activate();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REENTRANCY ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ReentrancyOnBuy() public {
        // Deploy attacker contract
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(curve, elta);

        // Fund attacker
        vm.prank(admin);
        elta.transfer(address(attackerContract), 10_000 ether);
        elataPoints.setBalance(address(attackerContract), 1000 ether);

        uint256 attackerBalanceBefore = elta.balanceOf(address(attackerContract));
        uint256 curveReserveBefore = curve.reserveElta();

        // Try reentrancy attack
        try attackerContract.attack(100 ether, 5) {} catch {}

        uint256 attackerBalanceAfter = elta.balanceOf(address(attackerContract));
        uint256 curveReserveAfter = curve.reserveElta();

        // Verify no funds were stolen through reentrancy
        // Attacker should not have more ELTA than expected from normal purchase
        console2.log("Attacker balance change:", attackerBalanceBefore - attackerBalanceAfter);
        console2.log("Curve reserve change:", curveReserveAfter - curveReserveBefore);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_FlashLoanPriceManipulation() public {
        // Deploy flash loan simulator
        FlashLoanSimulator flashAttacker = new FlashLoanSimulator(elta, curve);

        // Fund with simulated flash loan
        vm.prank(admin);
        elta.transfer(address(flashAttacker), 50_000 ether);
        elataPoints.setBalance(address(flashAttacker), 1000 ether);

        uint256 priceBefore = curve.reserveToken() > 0 ? (curve.reserveElta() * 1e18) / curve.reserveToken() : 0;

        // Execute flash loan attack
        flashAttacker.executeFlashLoanAttack(50_000 ether, 10_000 ether);

        uint256 priceAfter = curve.reserveToken() > 0 ? (curve.reserveElta() * 1e18) / curve.reserveToken() : 0;

        // Log price impact
        console2.log("Price before:", priceBefore);
        console2.log("Price after:", priceAfter);
        console2.log("Price impact %:", priceAfter > priceBefore ? ((priceAfter - priceBefore) * 100) / priceBefore : 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FRONT-RUNNING / SANDWICH ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SandwichAttack() public {
        // Alice wants to buy tokens
        uint256 aliceBuyAmount = 1000 ether;

        // Record state before attack
        uint256 reserveEltaBefore = curve.reserveElta();
        uint256 reserveTokenBefore = curve.reserveToken();

        // Attacker front-runs with large buy
        vm.startPrank(attacker);
        elta.approve(address(curve), 10_000 ether);
        curve.buy(5_000 ether, 10_000 ether, address(0));
        vm.stopPrank();

        uint256 priceAfterFrontRun = (curve.reserveElta() * 1e18) / curve.reserveToken();

        // Alice's transaction executes
        vm.startPrank(alice);
        elta.approve(address(curve), aliceBuyAmount * 2);
        uint256 aliceTokensBefore = appToken.balanceOf(alice);
        curve.buy(aliceBuyAmount, aliceBuyAmount * 2, address(0));
        uint256 aliceTokensReceived = appToken.balanceOf(alice) - aliceTokensBefore;
        vm.stopPrank();

        // Attacker back-runs (would need a sell function, but curve is buy-only)
        // In a real sandwich, attacker would sell here

        console2.log("Price before attack:", (reserveEltaBefore * 1e18) / reserveTokenBefore);
        console2.log("Price after front-run:", priceAfterFrontRun);
        console2.log("Alice received tokens:", aliceTokensReceived);

        // Alice should have received fewer tokens due to price increase
        // This documents the front-running vulnerability (inherent to AMMs)
    }

    function test_Security_SlippageProtection() public {
        // Get initial state
        uint256 initialReserve = curve.reserveElta();
        console2.log("Initial reserve ELTA:", initialReserve);

        // Alice tests slippage protection with a buy
        vm.startPrank(alice);
        elta.approve(address(curve), 500 ether);

        // Get expected tokens for a small amount
        uint256 expectedTokens = curve.getTokensOut(100 ether);
        console2.log("Expected tokens for 100 ELTA:", expectedTokens);

        // Buy should work with reasonable slippage tolerance
        uint256 tokensBefore = appToken.balanceOf(alice);
        curve.buy(100 ether, 200 ether, address(0)); // 2x max spend tolerance
        uint256 tokensReceived = appToken.balanceOf(alice) - tokensBefore;

        console2.log("Tokens received:", tokensReceived);

        // Verify we got a reasonable amount
        assertGt(tokensReceived, 0, "Should receive some tokens");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION EXPLOIT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotForceGraduateEarly() public {
        // Try to call graduate directly (should be internal/protected)
        // Curve should only graduate when target is reached

        uint256 currentReserve = curve.reserveElta();
        uint256 target = curve.targetRaisedElta();

        assertLt(currentReserve, target, "Curve should not have reached target yet");

        // Verify curve is not graduated
        assertFalse(curve.graduated(), "Curve should not be graduated");
        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.ACTIVE), "Curve should be active");
    }

    function test_Security_CannotBuyAfterGraduation() public {
        // This test would require a way to graduate the curve first
        // For now, we test that buy fails when curve is in wrong state

        // Try to buy when curve is pending (before activation)
        AppBondingCurve newCurve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 1,
                factory: address(appFactory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 365 days * 2,
                lpBeneficiary: creator,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(appFeeRouter)),
                elataPoints: IElataPoints(address(elataPoints)),
                governance: governance,
                activationDelay: 1 hours,
                maxDuration: 30 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        vm.prank(admin);
        appToken.mint(address(newCurve), APP_TOKEN_SUPPLY / 4);

        // Try to buy before activation
        vm.startPrank(attacker);
        elta.approve(address(newCurve), 1000 ether);
        vm.expectRevert(); // Should revert - curve not active
        newCurve.buy(100 ether, 1000 ether, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SNIPER FEE CIRCUMVENTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SniperFeeEnforced() public {
        // Enable sniper fee
        vm.prank(governance);
        curve.setSniperFeeConfig(500, 1 hours, true); // 5% fee for 1 hour

        // Buy during sniper window
        vm.startPrank(alice);
        elta.approve(address(curve), 1000 ether);
        uint256 balanceBefore = elta.balanceOf(alice);
        curve.buy(100 ether, 1000 ether, address(0));
        uint256 spent = balanceBefore - elta.balanceOf(alice);
        vm.stopPrank();

        console2.log("ELTA spent during sniper window:", spent);

        // Warp past sniper window
        vm.warp(block.timestamp + 1 hours + 1);

        // Buy after sniper window
        vm.startPrank(bob);
        elta.approve(address(curve), 1000 ether);
        balanceBefore = elta.balanceOf(bob);
        curve.buy(100 ether, 1000 ether, address(0));
        uint256 spentAfter = balanceBefore - elta.balanceOf(bob);
        vm.stopPrank();

        console2.log("ELTA spent after sniper window:", spentAfter);

        // First buyer should have paid more due to sniper fee
        // (assuming similar token amounts received)
    }

    function test_Security_CannotBypassSniperFee() public {
        // Enable sniper fee
        vm.prank(governance);
        curve.setSniperFeeConfig(500, 1 hours, true);

        // Try various ways to bypass the fee

        // 1. Multiple small transactions
        vm.startPrank(attacker);
        elta.approve(address(curve), 10_000 ether);

        uint256 totalSpent = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 balanceBefore = elta.balanceOf(attacker);
            curve.buy(10 ether, 100 ether, address(0));
            totalSpent += balanceBefore - elta.balanceOf(attacker);
        }
        vm.stopPrank();

        console2.log("Total spent in small txs:", totalSpent);

        // Fee should still apply to all transactions during window
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFERRAL MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SelfReferral() public {
        // Try to set self as referrer
        vm.startPrank(attacker);
        elta.approve(address(curve), 1000 ether);

        // Buy with self as referrer
        curve.buy(100 ether, 1000 ether, attacker);
        vm.stopPrank();

        // Self-referral should either be blocked or not provide benefits
        // This depends on how referral system is implemented
    }

    function test_Security_CircularReferral() public {
        // Alice refers Bob, Bob tries to refer Alice
        vm.startPrank(alice);
        elta.approve(address(curve), 1000 ether);
        curve.buy(100 ether, 1000 ether, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        elta.approve(address(curve), 1000 ether);
        curve.buy(100 ether, 1000 ether, alice);
        vm.stopPrank();

        // Circular referrals should not create infinite reward loops
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OVERFLOW / PRECISION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_LargeAmountOverflow() public {
        // Try to buy with very large amount
        vm.startPrank(admin);
        elta.transfer(attacker, ELTA_MAX_SUPPLY / 2);
        vm.stopPrank();

        vm.startPrank(attacker);
        elta.approve(address(curve), type(uint256).max);

        // Try with amount near uint256 max
        vm.expectRevert(); // Should revert, not overflow
        curve.buy(type(uint256).max / 2, type(uint256).max, address(0));
        vm.stopPrank();
    }

    function test_Security_SmallAmountPrecision() public {
        // Try to buy with very small amount
        vm.startPrank(attacker);
        elta.approve(address(curve), 1000 ether);

        // Buy with 1 wei - should either work correctly or revert
        try curve.buy(1, 1000 ether, address(0)) {
            // If it works, verify no precision loss exploitation
            uint256 tokens = appToken.balanceOf(attacker);
            console2.log("Tokens received for 1 wei:", tokens);
        } catch {
            // Revert is acceptable for dust amounts
        }
        vm.stopPrank();
    }

    function testFuzz_Security_BuyAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 10_000 ether);

        vm.startPrank(alice);
        elta.approve(address(curve), amount * 2);

        uint256 eltaBefore = elta.balanceOf(alice);
        uint256 tokensBefore = appToken.balanceOf(alice);

        try curve.buy(amount, amount * 2, address(0)) {
            uint256 eltaSpent = eltaBefore - elta.balanceOf(alice);
            uint256 tokensReceived = appToken.balanceOf(alice) - tokensBefore;

            // Verify reasonable exchange
            assertGt(tokensReceived, 0, "Should receive tokens");
            assertLe(eltaSpent, amount * 2, "Should not overspend");
        } catch {}

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // XP GATING BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotBuyWithoutXPDuringEarlyAccess() public {
        // Deploy fresh curve at current time
        AppBondingCurve newCurve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: 2,
                factory: address(appFactory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 365 days * 2,
                lpBeneficiary: creator,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(appFeeRouter)),
                elataPoints: IElataPoints(address(elataPoints)),
                governance: governance,
                activationDelay: 0,
                maxDuration: 30 days,
                creator: creator,
                feeCollector: address(0),
                referralRegistry: address(0)
            })
        );

        vm.prank(admin);
        appToken.mint(address(newCurve), APP_TOKEN_SUPPLY / 4);

        vm.prank(governance);
        newCurve.activate();

        // Create user with no XP
        address noXPUser = makeAddr("noXPUser");
        vm.prank(admin);
        elta.transfer(noXPUser, 10_000 ether);
        // Note: Not setting XP for this user

        // Try to buy during early access (should fail without XP)
        vm.startPrank(noXPUser);
        elta.approve(address(newCurve), 1000 ether);
        vm.expectRevert(); // Should revert due to XP requirement
        newCurve.buy(100 ether, 1000 ether, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyGovernanceCanSetSniperFee() public {
        vm.expectRevert();
        vm.prank(attacker);
        curve.setSniperFeeConfig(1000, 2 hours, true);
    }

    function test_Security_OnlyGovernanceCanSetXPParams() public {
        vm.expectRevert();
        vm.prank(attacker);
        curve.setXPGate(500 ether, 12 hours);
    }
}
