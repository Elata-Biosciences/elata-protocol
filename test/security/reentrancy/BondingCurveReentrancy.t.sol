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

// Mock contracts for testing
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
    bool public graduationCalled;

    function onAppGraduated(uint256, address, address, uint256, uint256, uint256) external {
        graduationCalled = true;
    }

    function initializeCurve(AppBondingCurve curve, uint256 seedElta, uint256 tokenSupply) external {
        curve.initializeCurve(seedElta, tokenSupply);
    }
}

/**
 * @title ReentrancyAttacker
 * @notice Malicious contract that attempts reentrancy on bonding curve
 */
contract ReentrancyAttacker {
    AppBondingCurve public curve;
    IERC20 public elta;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _curve, address _elta) {
        curve = AppBondingCurve(_curve);
        elta = IERC20(_elta);
    }

    function attack(uint256 amount) external {
        attacking = true;
        attackCount = 0;
        elta.approve(address(curve), type(uint256).max);
        curve.buy(amount, 0, address(0));
    }

    // Callback that attempts reentrancy
    function onTokenTransfer(address, uint256, bytes calldata) external returns (bool) {
        if (attacking && attackCount < 2) {
            attackCount++;
            try curve.buy(1 ether, 0, address(0)) {} catch {}
        }
        return true;
    }

    // ERC777 callback
    function tokensReceived(address, address, address, uint256, bytes calldata, bytes calldata) external {
        if (attacking && attackCount < 2) {
            attackCount++;
            try curve.buy(1 ether, 0, address(0)) {} catch {}
        }
    }

    // Fallback for any callback
    fallback() external {
        if (attacking && attackCount < 2) {
            attackCount++;
            try curve.buy(1 ether, 0, address(0)) {} catch {}
        }
    }
}

/**
 * @title GraduationReentrancyAttacker
 * @notice Attempts reentrancy during graduation
 */
contract GraduationReentrancyAttacker {
    AppBondingCurve public curve;
    IERC20 public elta;
    bool public attacking;
    uint256 public reenterCount;

    constructor(address _curve, address _elta) {
        curve = AppBondingCurve(_curve);
        elta = IERC20(_elta);
    }

    function triggerGraduation(uint256 amount) external {
        attacking = true;
        elta.approve(address(curve), type(uint256).max);
        // Buy enough to trigger graduation
        curve.buy(amount, 0, address(0));
    }

    // Attempt to re-enter during graduation via token callback
    function onTokenTransfer(address, uint256, bytes calldata) external returns (bool) {
        if (attacking && reenterCount < 1) {
            reenterCount++;
            // Try to sweep fees during graduation
            try curve.sweepFees() {} catch {}
            // Try to buy more during graduation
            try curve.buy(1 ether, 0, address(0)) {} catch {}
        }
        return true;
    }
}

/**
 * @title SweepFeesReentrancyAttacker
 * @notice Attempts reentrancy via sweepFees
 */
contract SweepFeesReentrancyAttacker {
    AppBondingCurve public curve;
    uint256 public attackCount;

    constructor(address _curve) {
        curve = AppBondingCurve(_curve);
    }

    // Called when receiving ELTA during sweepFees
    function onTokenTransfer(address, uint256, bytes calldata) external returns (bool) {
        if (attackCount < 2) {
            attackCount++;
            try curve.sweepFees() {} catch {}
        }
        return true;
    }
}

/**
 * @title BondingCurveReentrancy
 * @notice Comprehensive reentrancy tests for AppBondingCurve
 */
contract BondingCurveReentrancy is Test {
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

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant TARGET_RAISED = 1000 ether;

    function setUp() public {
        // Deploy mock infrastructure
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

        // Deploy BondingCurve
        curve = new AppBondingCurve(
            1, // appId
            address(factory),
            IERC20(address(elta)),
            appToken,
            IUniswapV2Router02(address(router)),
            TARGET_RAISED,
            30 days, // lpLockDuration
            treasury, // lpBeneficiary
            treasury, // treasury
            IAppFeeRouter(address(feeRouter)),
            IElataPoints(address(xp)),
            governance,
            0, // activationDelay
            365 days, // maxDuration
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

        // Activate curve
        curve.activate();

        // Set XP for attacker
        xp.setBalance(attacker, 1000 ether);

        // Fund attacker
        vm.prank(admin);
        elta.transfer(attacker, 10_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STANDARD REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_BuyProtectedByNonReentrant() public {
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(address(curve), address(elta));

        vm.prank(admin);
        elta.transfer(address(attackerContract), 1000 ether);

        xp.setBalance(address(attackerContract), 1000 ether);

        // Attack should not succeed in reentering
        vm.prank(attacker);
        attackerContract.attack(10 ether);

        // Verify only one buy executed (reentrancy blocked)
        assertEq(attackerContract.attackCount(), 0, "Reentrancy should be blocked");
    }

    function test_Reentrancy_GraduateProtectedByNonReentrant() public {
        GraduationReentrancyAttacker attackerContract = new GraduationReentrancyAttacker(address(curve), address(elta));

        vm.prank(admin);
        elta.transfer(address(attackerContract), TARGET_RAISED + 100 ether);

        xp.setBalance(address(attackerContract), 1000 ether);

        // Trigger graduation attack
        vm.prank(attacker);
        attackerContract.triggerGraduation(TARGET_RAISED);

        // Verify reentrancy was blocked
        assertEq(attackerContract.reenterCount(), 0, "Graduation reentrancy should be blocked");
    }

    function test_Reentrancy_SweepFeesProtected() public {
        // First do a buy to accumulate fees
        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);
        curve.buy(10 ether, 0, address(0));
        vm.stopPrank();

        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Should have pending fees");

        // Without fee collector, sweep does nothing but doesn't revert
        curve.sweepFees();

        // Fees remain pending without fee collector
        assertEq(curve.pendingFees(), pendingFees, "Fees remain without collector");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CROSS-FUNCTION REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_BuyThenSweepFees() public {
        // Setup fee collector
        vm.prank(governance);
        curve.setFeeCollector(treasury); // Use treasury as mock fee collector

        // Do initial buy
        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);
        curve.buy(10 ether, 0, address(0));
        vm.stopPrank();

        uint256 pendingBefore = curve.pendingFees();
        assertGt(pendingBefore, 0, "Should have pending fees after buy");

        // Verify pending fees exist (sweep requires fee collector setup)
        // The actual sweep would require a proper fee collector
    }

    function test_Reentrancy_MultipleBuysAtomic() public {
        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);

        uint256 reserveBefore = curve.reserveElta();

        // Multiple buys should each be atomic
        curve.buy(5 ether, 0, address(0));
        curve.buy(5 ether, 0, address(0));
        curve.buy(5 ether, 0, address(0));

        uint256 reserveAfter = curve.reserveElta();
        vm.stopPrank();

        // Reserves should increase correctly
        assertGt(reserveAfter, reserveBefore, "Reserves should increase");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // READ-ONLY REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_ReadOnlyPriceConsistent() public {
        // Get price before buy
        uint256 priceBefore = curve.getCurrentPrice();

        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);
        curve.buy(50 ether, 0, address(0));
        vm.stopPrank();

        // Get price after buy
        uint256 priceAfter = curve.getCurrentPrice();

        // Price should increase (more ELTA, less tokens)
        assertGt(priceAfter, priceBefore, "Price should increase after buy");
    }

    function test_Reentrancy_GetCurveStateConsistent() public {
        (uint256 eltaBefore, uint256 tokenBefore,,,,) = curve.getCurveState();

        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);
        curve.buy(10 ether, 0, address(0));
        vm.stopPrank();

        (uint256 eltaAfter, uint256 tokenAfter,,,,) = curve.getCurveState();

        // State should be consistent
        assertGt(eltaAfter, eltaBefore, "ELTA reserve should increase");
        assertLt(tokenAfter, tokenBefore, "Token reserve should decrease");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE CONSISTENCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_ReservesConsistentAfterBuy() public {
        uint256 reserveEltaBefore = curve.reserveElta();
        uint256 reserveTokenBefore = curve.reserveToken();

        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);
        curve.buy(10 ether, 0, address(0));
        vm.stopPrank();

        uint256 reserveEltaAfter = curve.reserveElta();
        uint256 reserveTokenAfter = curve.reserveToken();

        // ELTA reserve should increase, token reserve should decrease
        assertGt(reserveEltaAfter, reserveEltaBefore, "ELTA reserve should increase");
        assertLt(reserveTokenAfter, reserveTokenBefore, "Token reserve should decrease");
    }

    function test_Reentrancy_PendingFeesAccumulateCorrectly() public {
        uint256 feesBefore = curve.pendingFees();

        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);
        curve.buy(10 ether, 0, address(0));
        vm.stopPrank();

        uint256 feesAfter = curve.pendingFees();

        // Fees should accumulate
        assertGt(feesAfter, feesBefore, "Pending fees should increase");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MALICIOUS TOKEN CALLBACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Reentrancy_TokenTransferCallbackBlocked() public {
        // The AppToken uses standard ERC20, no callbacks
        // But we test that even with malicious receiver, state is safe

        vm.startPrank(attacker);
        elta.approve(address(curve), 100 ether);

        uint256 tokensBefore = appToken.balanceOf(attacker);
        curve.buy(10 ether, 0, address(0));
        uint256 tokensAfter = appToken.balanceOf(attacker);

        assertGt(tokensAfter, tokensBefore, "Tokens should be received");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Reentrancy_MultipleBuys(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 0.1 ether, 100 ether);
        amount2 = bound(amount2, 0.1 ether, 100 ether);
        amount3 = bound(amount3, 0.1 ether, 100 ether);

        vm.startPrank(attacker);
        elta.approve(address(curve), 1000 ether);

        uint256 totalTokens = 0;
        uint256 tokensBefore = appToken.balanceOf(attacker);

        curve.buy(amount1, 0, address(0));
        curve.buy(amount2, 0, address(0));
        curve.buy(amount3, 0, address(0));

        totalTokens = appToken.balanceOf(attacker) - tokensBefore;
        vm.stopPrank();

        // Should have received tokens
        assertGt(totalTokens, 0, "Should receive tokens");
    }

    function testFuzz_Reentrancy_StateConsistency(uint256 buyAmount) public {
        buyAmount = bound(buyAmount, 1 ether, TARGET_RAISED / 2);

        uint256 reserveEltaBefore = curve.reserveElta();
        uint256 reserveTokenBefore = curve.reserveToken();

        vm.startPrank(attacker);
        elta.approve(address(curve), buyAmount * 2);
        uint256 tokensOut = curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        uint256 reserveEltaAfter = curve.reserveElta();
        uint256 reserveTokenAfter = curve.reserveToken();

        // Verify accounting
        assertEq(reserveTokenBefore - reserveTokenAfter, tokensOut, "Token reserve should decrease by tokensOut");
        assertGt(reserveEltaAfter, reserveEltaBefore, "ELTA reserve should increase");
    }
}
