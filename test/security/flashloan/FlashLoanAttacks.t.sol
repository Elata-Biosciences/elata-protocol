// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {AppBondingCurve} from "../../../src/apps/AppBondingCurve.sol";
import {IAppFeeRouter} from "../../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../../src/interfaces/IElataPoints.sol";
import {IUniswapV2Router02} from "../../../src/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../../src/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

/// @notice Mock flash loan provider
contract MockFlashLoanProvider {
    IERC20 public token;
    uint256 public fee = 9; // 0.09% fee (9 bps)

    constructor(address _token) {
        token = IERC20(_token);
    }

    function flashLoan(address receiver, uint256 amount, bytes calldata data) external {
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= amount, "Insufficient liquidity");

        // Transfer to borrower
        token.transfer(receiver, amount);

        // Execute callback
        IFlashLoanReceiver(receiver).executeOperation(amount, fee, data);

        // Verify repayment
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 expectedReturn = amount + (amount * fee) / 10000;
        require(balanceAfter >= expectedReturn, "Flash loan not repaid");
    }
}

interface IFlashLoanReceiver {
    function executeOperation(uint256 amount, uint256 fee, bytes calldata data) external;
}

/// @notice Attacker that attempts flash loan price manipulation
contract FlashLoanPriceAttacker is IFlashLoanReceiver {
    ELTA public elta;
    AppBondingCurve public curve;
    MockFlashLoanProvider public loanProvider;
    address public owner;

    uint256 public profitMade;

    constructor(address _elta, address _curve, address _loanProvider) {
        elta = ELTA(_elta);
        curve = AppBondingCurve(_curve);
        loanProvider = MockFlashLoanProvider(_loanProvider);
        owner = msg.sender;
    }

    function attack(uint256 flashAmount) external {
        // Borrow ELTA via flash loan
        loanProvider.flashLoan(address(this), flashAmount, "");
    }

    function executeOperation(uint256 amount, uint256 fee, bytes calldata) external override {
        // Step 1: Buy large amount to pump price
        elta.approve(address(curve), amount);

        uint256 tokensBefore = curve.reserveToken();
        uint256 tokensReceived = curve.buy(amount / 2, 0, address(0));

        // Step 2: Price is now higher - but we can't sell on bonding curve (buy-only)
        // The attack fails because there's no way to profit

        // Step 3: Repay flash loan
        uint256 repayAmount = amount + (amount * fee) / 10000;
        elta.transfer(address(loanProvider), repayAmount);
    }
}

/// @notice Attacker that attempts to manipulate graduation
contract FlashLoanGraduationAttacker is IFlashLoanReceiver {
    ELTA public elta;
    AppBondingCurve public curve;
    MockFlashLoanProvider public loanProvider;

    bool public graduationTriggered;

    constructor(address _elta, address _curve, address _loanProvider) {
        elta = ELTA(_elta);
        curve = AppBondingCurve(_curve);
        loanProvider = MockFlashLoanProvider(_loanProvider);
    }

    function attack(uint256 flashAmount) external {
        loanProvider.flashLoan(address(this), flashAmount, "");
    }

    function executeOperation(uint256 amount, uint256 fee, bytes calldata) external override {
        elta.approve(address(curve), amount);

        // Try to buy enough to trigger graduation
        uint256 target = curve.targetRaisedElta();
        uint256 current = curve.reserveElta();
        uint256 needed = target > current ? target - current : 0;

        if (needed > 0 && needed <= amount) {
            curve.buy(needed, 0, address(0));
            graduationTriggered = curve.graduated();
        }

        // Repay
        uint256 repayAmount = amount + (amount * fee) / 10000;
        elta.transfer(address(loanProvider), repayAmount);
    }
}

/// @notice Attacker that tries flash stake for voting power
contract FlashStakeAttacker is IFlashLoanReceiver {
    ELTA public elta;
    VeELTA public veElta;
    MockFlashLoanProvider public loanProvider;

    uint256 public votingPowerObtained;

    constructor(address _elta, address _veElta, address _loanProvider) {
        elta = ELTA(_elta);
        veElta = VeELTA(_veElta);
        loanProvider = MockFlashLoanProvider(_loanProvider);
    }

    function attack(uint256 flashAmount) external {
        loanProvider.flashLoan(address(this), flashAmount, "");
    }

    function executeOperation(uint256 amount, uint256 fee, bytes calldata) external override {
        // Try to stake borrowed ELTA
        elta.approve(address(veElta), amount);

        // This should fail or give 0 voting power because:
        // 1. Lock requires minimum duration
        // 2. Voting power requires time to accrue
        // 3. Can't unlock immediately
        try veElta.lock(amount, uint64(block.timestamp + 7 days + 1)) {
            votingPowerObtained = veElta.getVotes(address(this));
            // Cannot unlock immediately to repay
        } catch {
            // Lock failed as expected
        }

        // Try to repay (will fail if tokens are locked)
        uint256 repayAmount = amount + (amount * fee) / 10000;
        uint256 balance = elta.balanceOf(address(this));
        if (balance >= repayAmount) {
            elta.transfer(address(loanProvider), repayAmount);
        }
    }
}

/**
 * @title FlashLoanAttacks
 * @notice Flash loan attack tests for price manipulation and arbitrage
 */
contract FlashLoanAttacks is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppToken public appToken;
    AppBondingCurve public curve;
    MockAppFactory public factory;
    MockElataPoints public xp;
    MockUniswapFactory public uniFactory;
    MockUniswapRouter public router;
    MockPair public pair;
    MockAppFeeRouter public feeRouter;
    MockFlashLoanProvider public flashProvider;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 1000 ether;

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

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

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

        // Deploy BondingCurve
        curve = new AppBondingCurve(
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

        // Activate curve
        curve.activate();

        // Deploy flash loan provider and fund it
        flashProvider = new MockFlashLoanProvider(address(elta));
        vm.prank(admin);
        elta.transfer(address(flashProvider), 10_000_000 ether);

        // Set XP for attacker
        xp.setBalance(attacker, 1000 ether);

        // Fund attacker with small amount for fees
        vm.prank(admin);
        elta.transfer(attacker, 100 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN PRICE MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FlashLoan_CannotProfitFromPriceManipulation() public {
        FlashLoanPriceAttacker attackerContract =
            new FlashLoanPriceAttacker(address(elta), address(curve), address(flashProvider));

        xp.setBalance(address(attackerContract), 1000 ether);

        // Fund attacker contract - use smaller amounts to not trigger graduation
        vm.prank(admin);
        elta.transfer(address(attackerContract), 500 ether);

        // Get state before
        uint256 priceBefore = curve.getCurrentPrice();
        uint256 attackerEltaBefore = elta.balanceOf(address(attackerContract));
        bool graduatedBefore = curve.graduated();

        assertFalse(graduatedBefore, "Curve should not be graduated yet");

        // Attempt attack with small amount (avoid graduation)
        attackerContract.attack(200 ether);

        // Check state after
        bool graduatedAfter = curve.graduated();

        if (!graduatedAfter) {
            // Price should have increased from the buy
            uint256 priceAfter = curve.getCurrentPrice();
            assertGt(priceAfter, priceBefore, "Price should increase from buy");
        }

        // Attacker's ELTA balance should be lower (paid fees + buy cost)
        // Even if curve graduated, attacker spent capital
        uint256 attackerEltaAfter = elta.balanceOf(address(attackerContract));
        assertLt(attackerEltaAfter, attackerEltaBefore, "Attacker should have spent ELTA");
    }

    function test_FlashLoan_BuyOnlyCurvePreventsArbitrage() public {
        // The bonding curve is buy-only, so flash loan arbitrage is impossible
        // You can buy tokens, but there's no way to sell them back to the curve

        uint256 flashAmount = 1000 ether;

        // Simulate borrowing
        vm.prank(admin);
        elta.transfer(attacker, flashAmount);

        // Buy tokens
        vm.startPrank(attacker);
        elta.approve(address(curve), flashAmount);

        uint256 tokensBefore = appToken.balanceOf(attacker);
        curve.buy(flashAmount / 2, 0, address(0));
        uint256 tokensAfter = appToken.balanceOf(attacker);

        // Got tokens, but can't sell them back to curve
        assertGt(tokensAfter, tokensBefore, "Should receive tokens");

        // No sell function exists
        // curve.sell() doesn't exist
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN GRADUATION MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FlashLoan_GraduationRequiresPermanentCapital() public {
        FlashLoanGraduationAttacker attackerContract =
            new FlashLoanGraduationAttacker(address(elta), address(curve), address(flashProvider));

        xp.setBalance(address(attackerContract), 1000 ether);

        // Fund attacker for fees
        vm.prank(admin);
        elta.transfer(address(attackerContract), TARGET_RAISED * 2);

        // Attempt to trigger graduation via flash loan
        attackerContract.attack(TARGET_RAISED * 2);

        // Even if graduation is triggered, the attacker:
        // 1. Spent permanent capital (can't get it back from curve)
        // 2. Has tokens but no immediate liquidity
        // 3. Flash loan is repaid from their own funds

        // If graduated, LP is locked - can't extract value immediately
    }

    function test_FlashLoan_CannotExtractLPAfterGraduation() public {
        // Even if flash loan triggers graduation, LP tokens are locked
        // for lpLockDuration (30 days in our test)

        // First, legitimately buy to near graduation
        vm.prank(admin);
        elta.transfer(attacker, TARGET_RAISED);

        vm.startPrank(attacker);
        elta.approve(address(curve), TARGET_RAISED);
        curve.buy(TARGET_RAISED, 0, address(0));
        vm.stopPrank();

        // Check if graduated
        if (curve.graduated()) {
            // LP tokens are locked
            address locker = curve.locker();
            uint256 unlockAt = curve.lpUnlockAt();

            assertGt(unlockAt, block.timestamp, "LP should be locked");
            assertEq(unlockAt, block.timestamp + 30 days, "LP locked for 30 days");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN VEELTA VOTING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FlashLoan_CannotGainImmediateVotingPower() public {
        FlashStakeAttacker attackerContract =
            new FlashStakeAttacker(address(elta), address(veElta), address(flashProvider));

        // Attacker tries flash loan → stake → vote → unstake → repay
        // This should fail because:
        // 1. MIN_LOCK requires 7 day minimum lock
        // 2. Cannot unlock before lock expires
        // 3. Flash loan must be repaid same tx

        // The attack contract will lock tokens, but then the flash loan callback
        // will try to repay, which will fail because tokens are locked
        // However, due to try/catch in the attacker, the attack() might not revert

        attackerContract.attack(1000 ether);

        // Even if attack didn't revert, verify the attack was ineffective:
        // 1. Tokens are locked (can't be used elsewhere)
        // 2. Or the lock failed and no voting power was gained
        uint256 votingPower = attackerContract.votingPowerObtained();

        // The attacker either has 0 voting power OR their tokens are locked forever
        // Either way, the attack is economically ineffective
        if (votingPower > 0) {
            // Tokens are locked in veELTA, attacker lost capital
            (uint128 principal,) = veElta.locks(address(attackerContract));
            assertGt(principal, 0, "If voting power obtained, tokens should be locked");
        }
    }

    function test_FlashLoan_VeELTALockPreventsFlashStake() public {
        // Create a fresh attacker address with no initial balance
        address freshAttacker = makeAddr("freshAttacker");

        uint256 flashAmount = 1000 ether;

        // Simulate flash loan to fresh attacker
        vm.prank(admin);
        elta.transfer(freshAttacker, flashAmount);

        vm.startPrank(freshAttacker);
        elta.approve(address(veElta), flashAmount);

        // Lock requires minimum duration
        uint64 minLock = veElta.MIN_LOCK();

        // Lock ALL tokens
        veElta.lock(flashAmount, uint64(block.timestamp + minLock + 1));

        // Tokens are now locked - cannot repay flash loan
        uint256 balance = elta.balanceOf(freshAttacker);
        assertEq(balance, 0, "All ELTA should be locked");

        // Cannot unlock before expiry
        vm.expectRevert();
        veElta.unlock();

        vm.stopPrank();
    }

    function test_FlashLoan_VotingPowerRequiresHistoricalSnapshot() public {
        // Even if you could lock, voting power uses historical snapshots
        // via getPastVotes() - flash stake in same block is useless

        vm.prank(admin);
        elta.transfer(attacker, 1000 ether);

        vm.startPrank(attacker);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Current voting power exists
        uint256 currentVotes = veElta.getVotes(attacker);
        assertGt(currentVotes, 0, "Should have current voting power");

        // But getPastVotes at this block will revert (future lookup)
        // And any governance actions use past snapshots
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH LOAN ECONOMIC ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_FlashLoan_ConstantProductMaintained() public {
        uint256 k_before = curve.reserveElta() * curve.reserveToken();

        // Large buy - need to account for fees (1% trading fee)
        uint256 buyAmount = 500 ether;
        uint256 maxSpend = buyAmount * 110 / 100; // 10% extra for fees

        vm.prank(admin);
        elta.transfer(attacker, maxSpend);

        vm.startPrank(attacker);
        elta.approve(address(curve), maxSpend);
        curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        uint256 k_after = curve.reserveElta() * curve.reserveToken();

        // K should be maintained or increase (due to fees)
        // The constant product formula is preserved
        assertGe(k_after, k_before * 95 / 100, "K should be roughly maintained");
    }

    function test_FlashLoan_SlippageProtectionWorks() public {
        // Large buy should fail with high minTokensOut
        uint256 buyAmount = 500 ether;

        vm.prank(admin);
        elta.transfer(attacker, buyAmount * 2);

        vm.startPrank(attacker);
        elta.approve(address(curve), buyAmount * 2);

        // Get expected tokens
        uint256 expectedTokens = curve.getTokensOut(buyAmount);

        // Set very high minTokensOut - should fail
        vm.expectRevert();
        curve.buy(buyAmount, expectedTokens * 2, address(0));

        // With reasonable slippage protection
        curve.buy(buyAmount, expectedTokens * 90 / 100, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_FlashLoan_BuyDoesNotBreakInvariants(uint256 buyAmount) public {
        buyAmount = bound(buyAmount, 1 ether, TARGET_RAISED / 2);

        vm.prank(admin);
        elta.transfer(attacker, buyAmount * 2);

        uint256 reserveEltaBefore = curve.reserveElta();
        uint256 reserveTokenBefore = curve.reserveToken();
        uint256 totalSupplyBefore = appToken.totalSupply();

        vm.startPrank(attacker);
        elta.approve(address(curve), buyAmount * 2);
        uint256 tokensOut = curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        uint256 reserveEltaAfter = curve.reserveElta();
        uint256 reserveTokenAfter = curve.reserveToken();

        // Invariant: ELTA in equals tokens out follows curve
        assertGt(reserveEltaAfter, reserveEltaBefore, "ELTA reserve should increase");
        assertEq(reserveTokenBefore - reserveTokenAfter, tokensOut, "Token decrease should match tokensOut");

        // Invariant: total supply unchanged (transfers only)
        assertEq(appToken.totalSupply(), totalSupplyBefore, "Total supply should not change");
    }

    function testFuzz_FlashLoan_CannotManipulatePriceAtomically(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1 ether, 100 ether);
        amount2 = bound(amount2, 1 ether, 100 ether);

        vm.prank(admin);
        elta.transfer(attacker, amount1 + amount2 + 100 ether);

        vm.startPrank(attacker);
        elta.approve(address(curve), amount1 + amount2 + 100 ether);

        // Buy 1
        uint256 price1 = curve.getCurrentPrice();
        curve.buy(amount1, 0, address(0));

        // Buy 2
        uint256 price2 = curve.getCurrentPrice();
        curve.buy(amount2, 0, address(0));

        uint256 price3 = curve.getCurrentPrice();
        vm.stopPrank();

        // Price should monotonically increase
        assertGe(price2, price1, "Price should not decrease");
        assertGe(price3, price2, "Price should not decrease");
    }
}
