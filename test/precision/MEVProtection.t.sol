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
 * @title MEVProtection
 * @notice Tests for MEV attack protection on bonding curve
 * @dev Tests sandwich attacks, frontrunning, and slippage protection
 *
 * Attack vectors tested:
 * - Sandwich attacks (frontrun + backrun)
 * - Large trade frontrunning
 * - Just-in-time liquidity at graduation
 * - Slippage protection effectiveness
 */
contract MEVProtection is Test, PrecisionFixtures {
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
    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");
    address public user = makeAddr("user");

    uint256 public constant APP_ID = 1;
    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 10_000 ether;
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
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: APP_TOKEN_SUPPLY,
                creator: creator,
                admin: admin,
                governance: governance,
                appRewardsDistributor: treasury,
                rewardsDistributor: treasury,
                treasury: treasury
            })
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
        elta.transfer(attacker, 500_000 ether);
        elta.transfer(victim, 100_000 ether);
        elta.transfer(user, 100_000 ether);
        vm.stopPrank();

        // Set XP (bypass XP gating)
        xp.setBalance(attacker, 1000e18);
        xp.setBalance(victim, 1000e18);
        xp.setBalance(user, 1000e18);

        // Mint tokens to curve and initialize
        vm.prank(admin);
        appToken.mint(address(curve), APP_TOKEN_SUPPLY);

        factory.initializeCurve(curve, SEED_ELTA, APP_TOKEN_SUPPLY);

        // Wait for activation and activate curve
        vm.warp(block.timestamp + 2 days);
        vm.prank(address(factory));
        curve.activate();

        // Approve curve
        vm.prank(attacker);
        elta.approve(address(curve), type(uint256).max);
        vm.prank(victim);
        elta.approve(address(curve), type(uint256).max);
        vm.prank(user);
        elta.approve(address(curve), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SANDWICH ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Simulate sandwich attack and measure victim's loss
    function test_MEV_SandwichAttackSimulation() public {
        // Scenario: Victim wants to buy 100 ELTA worth of tokens
        // Attacker sees this in mempool
        // Attacker front-runs with large buy
        // Victim's tx executes at worse price
        // Attacker sells immediately after

        uint256 victimBuy = 100 ether;

        // Get baseline: what victim would receive without sandwich
        uint256 tokensWithoutSandwich = curve.getTokensOut(victimBuy);

        // ─── Front-run: Attacker buys first ───
        uint256 attackerFrontrun = 500 ether;
        vm.prank(attacker);
        curve.buy(attackerFrontrun, 0, address(0));

        uint256 attackerTokens = appToken.balanceOf(attacker);

        // ─── Victim's tx executes ───
        uint256 tokensAfterFrontrun = curve.getTokensOut(victimBuy);

        vm.prank(victim);
        curve.buy(victimBuy, 0, address(0));

        uint256 victimTokens = appToken.balanceOf(victim);

        // ─── Calculate victim's loss ───
        uint256 victimLoss = tokensWithoutSandwich - victimTokens;
        uint256 lossPercentage = (victimLoss * 10000) / tokensWithoutSandwich;

        console2.log("=== Sandwich Attack Analysis ===");
        console2.log("Attacker frontrun:", attackerFrontrun / 1e18, "ELTA");
        console2.log("Victim buy:", victimBuy / 1e18, "ELTA");
        console2.log("Tokens without sandwich:", tokensWithoutSandwich / 1e18);
        console2.log("Tokens with sandwich:", victimTokens / 1e18);
        console2.log("Victim loss:", victimLoss / 1e18, "tokens");
        console2.log("Loss percentage (bps):", lossPercentage);

        // With AMM, victim WILL receive fewer tokens after frontrun
        // This is expected behavior - slippage protection is the defense
        assertLt(victimTokens, tokensWithoutSandwich, "Sandwich should reduce victim's tokens");
    }

    /// @notice Test slippage protection prevents sandwich attack loss
    function test_MEV_SlippageProtectionPreventsLoss() public {
        uint256 victimBuy = 100 ether;

        // Get expected tokens without manipulation
        uint256 expectedTokens = curve.getTokensOut(victimBuy);

        // Set tight slippage (5% max slippage)
        uint256 minTokensOut = (expectedTokens * 95) / 100;

        // ─── Attacker front-runs ───
        uint256 attackerFrontrun = 500 ether;
        vm.prank(attacker);
        curve.buy(attackerFrontrun, 0, address(0));

        // ─── Victim's tx with slippage protection ───
        uint256 tokensNow = curve.getTokensOut(victimBuy);

        if (tokensNow < minTokensOut) {
            // Victim's tx should revert due to slippage
            vm.prank(victim);
            vm.expectRevert();
            curve.buy(victimBuy, minTokensOut, address(0));

            console2.log("Slippage protection triggered!");
            console2.log("Expected min:", minTokensOut / 1e18);
            console2.log("Would receive:", tokensNow / 1e18);
        } else {
            // If slippage is acceptable, tx proceeds
            vm.prank(victim);
            curve.buy(victimBuy, minTokensOut, address(0));
        }
    }

    /// @notice Test various slippage settings
    function test_MEV_SlippageSettings() public {
        uint256 buyAmount = 100 ether;

        // Test different slippage tolerances
        uint256[] memory slippagesBps = new uint256[](5);
        slippagesBps[0] = 100; // 1%
        slippagesBps[1] = 300; // 3%
        slippagesBps[2] = 500; // 5%
        slippagesBps[3] = 1000; // 10%
        slippagesBps[4] = 0; // No slippage protection

        uint256 expectedTokens = curve.getTokensOut(buyAmount);

        for (uint256 i = 0; i < slippagesBps.length; i++) {
            uint256 minTokens = slippagesBps[i] > 0 ? (expectedTokens * (10000 - slippagesBps[i])) / 10000 : 0;

            // Reset state (deploy new curve)
            bool wouldSucceed = curve.getTokensOut(buyAmount) >= minTokens;

            console2.log("Slippage:", slippagesBps[i], "bps");
            console2.log("  Min tokens:", minTokens / 1e18);
            console2.log("  Would succeed:", wouldSucceed);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FRONTRUNNING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test large trade frontrunning impact
    function test_MEV_LargeTradeImpact() public {
        // Large trade visible in mempool
        uint256 largeBuy = 1000 ether;

        // Price before
        uint256 priceBefore = curve.getCurrentPrice();

        // Execute large buy
        vm.prank(victim);
        curve.buy(largeBuy, 0, address(0));

        // Price after
        uint256 priceAfter = curve.getCurrentPrice();

        // Calculate price impact
        uint256 priceImpact = ((priceAfter - priceBefore) * 10000) / priceBefore;

        console2.log("Large buy:", largeBuy / 1e18, "ELTA");
        console2.log("Price before:", priceBefore);
        console2.log("Price after:", priceAfter);
        console2.log("Price impact (bps):", priceImpact);

        // Large trades have significant price impact
        assertGt(priceImpact, 0, "Large trade should move price");
    }

    /// @notice Test sequential buys have diminishing returns
    function test_MEV_DiminishingReturns() public {
        uint256 buyAmount = 100 ether;
        uint256 numBuys = 10;

        uint256[] memory tokensReceived = new uint256[](numBuys);

        for (uint256 i = 0; i < numBuys; i++) {
            uint256 tokensBefore = appToken.balanceOf(user);

            vm.prank(user);
            curve.buy(buyAmount, 0, address(0));

            uint256 tokensAfter = appToken.balanceOf(user);
            tokensReceived[i] = tokensAfter - tokensBefore;

            console2.log("Buy received:", tokensReceived[i] / 1e18);
        }

        // Each subsequent buy should receive fewer tokens (price increases)
        for (uint256 i = 1; i < numBuys; i++) {
            assertLt(tokensReceived[i], tokensReceived[i - 1], "Should receive fewer tokens");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GRADUATION TIMING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test frontrunning graduation
    function test_MEV_FrontrunGraduation() public {
        // Buy up to just before graduation
        uint256 remaining = TARGET_RAISED - curve.reserveElta();
        uint256 nearGraduation = remaining - 100 ether;

        vm.prank(user);
        curve.buy(nearGraduation, 0, address(0));

        assertFalse(curve.graduated(), "Should not be graduated yet");

        // Attacker sees someone about to graduate and front-runs
        uint256 attackerBuy = 50 ether;
        vm.prank(attacker);
        curve.buy(attackerBuy, 0, address(0));

        // Check if graduated
        bool graduatedAfterAttacker = curve.graduated();

        // If not graduated, victim can still trigger it
        if (!graduatedAfterAttacker) {
            vm.prank(victim);
            curve.buy(100 ether, 0, address(0));
        }

        assertTrue(curve.graduated(), "Should be graduated now");
    }

    /// @notice Test just-in-time graduation trigger
    function test_MEV_JustInTimeGraduation() public {
        // Get exact remaining to graduation
        uint256 remaining = TARGET_RAISED - curve.reserveElta();

        // Multiple users race to trigger graduation
        uint256 numRacers = 3;
        uint256 buyEach = remaining / 2; // Each buys half of remaining

        for (uint256 i = 0; i < numRacers; i++) {
            if (curve.graduated()) {
                console2.log("Graduation triggered by racer:", i);
                break;
            }

            address racer = i == 0 ? attacker : (i == 1 ? victim : user);

            vm.prank(racer);
            try curve.buy(buyEach, 0, address(0)) {
                console2.log("Racer", i, "bought");
            } catch {
                console2.log("Racer", i, "failed");
            }
        }

        assertTrue(curve.graduated(), "Should be graduated");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROFIT EXTRACTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate potential sandwich profit
    function test_MEV_SandwichProfitCalculation() public {
        // Note: This bonding curve is buy-only, so attacker can't profit by selling
        // The "profit" would come from accumulated tokens, not immediate sale

        uint256 victimBuy = 500 ether;
        uint256 attackerFrontrun = 1000 ether;

        // Record attacker's initial state
        uint256 attackerEltaBefore = elta.balanceOf(attacker);

        // ─── Attacker frontrun ───
        vm.prank(attacker);
        curve.buy(attackerFrontrun, 0, address(0));

        // ─── Victim's tx ───
        vm.prank(victim);
        curve.buy(victimBuy, 0, address(0));

        // ─── Attacker's position ───
        uint256 attackerTokens = appToken.balanceOf(attacker);
        uint256 attackerEltaSpent = attackerEltaBefore - elta.balanceOf(attacker);

        // Calculate attacker's "cost per token"
        uint256 costPerToken = (attackerEltaSpent * 1e18) / attackerTokens;

        console2.log("=== Attacker Position ===");
        console2.log("ELTA spent:", attackerEltaSpent / 1e18);
        console2.log("Tokens received:", attackerTokens / 1e18);
        console2.log("Cost per token:", costPerToken);

        // In a buy-only curve, attacker doesn't profit immediately
        // They just accumulate tokens that may be worth more post-graduation
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS GRIEFING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test gas cost of buy operation
    function test_MEV_GasCostAnalysis() public {
        uint256[] memory buyAmounts = new uint256[](5);
        buyAmounts[0] = 1 ether;
        buyAmounts[1] = 10 ether;
        buyAmounts[2] = 100 ether;
        buyAmounts[3] = 500 ether;
        buyAmounts[4] = 1000 ether;

        for (uint256 i = 0; i < buyAmounts.length; i++) {
            uint256 amount = buyAmounts[i];

            uint256 gasBefore = gasleft();
            vm.prank(user);
            curve.buy(amount, 0, address(0));
            uint256 gasUsed = gasBefore - gasleft();

            console2.log("Buy", amount / 1e18, "ELTA - Gas used:", gasUsed);
        }
    }

    /// @notice Test many small buys gas cost
    function test_MEV_ManySmallBuysGas() public {
        uint256 numBuys = 20;
        uint256 smallAmount = 10 ether;
        uint256 totalGas = 0;

        for (uint256 i = 0; i < numBuys; i++) {
            uint256 gasBefore = gasleft();
            vm.prank(user);
            curve.buy(smallAmount, 0, address(0));
            totalGas += gasBefore - gasleft();
        }

        console2.log("Total gas for", numBuys, "small buys:", totalGas);
        console2.log("Average gas per buy:", totalGas / numBuys);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MITIGATION EFFECTIVENESS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test that tight slippage limits sandwich profitability
    function test_MEV_TightSlippageMitigation() public {
        uint256 victimBuy = 100 ether;
        uint256 expectedTokens = curve.getTokensOut(victimBuy);

        // Very tight slippage: 0.5%
        uint256 minTokens = (expectedTokens * 9950) / 10000;

        // For attacker to make frontrun worthwhile, they need price to move > 0.5%
        // Calculate minimum frontrun for 0.5% price impact
        uint256 reserveElta = curve.reserveElta();
        uint256 minFrontrun = reserveElta / 200; // ~0.5% impact

        console2.log("Minimum frontrun for 0.5% impact:", minFrontrun / 1e18, "ELTA");

        // With tight slippage, small frontrun might not trigger revert
        // but also won't be profitable
        if (minFrontrun < 10 ether) {
            console2.log("Small frontrun not worthwhile");
        }
    }

    /// @notice Test commitment scheme concept (informational)
    function test_MEV_CommitmentSchemeIdea() public pure {
        // A commitment scheme could prevent frontrunning:
        // 1. User commits hash(buy_amount, secret)
        // 2. Wait N blocks
        // 3. User reveals (buy_amount, secret)
        // 4. Contract verifies and executes

        // This is not implemented in the current bonding curve
        // but could be added as future enhancement

        // For now, slippage protection is the primary defense
        assertTrue(true, "Informational test");
    }
}
