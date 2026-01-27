// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
// import {LpLocker} from "../../src/apps/LpLocker.sol";
import {ELTA} from "elta/ELTA.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../../src/interfaces/IUniswapV2Factory.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ElataPoints for testing
contract MockElataPoints is ERC20 {
    mapping(address => uint256) private _xpBalances;

    constructor() ERC20("ElataPoints", "XP") {}

    function setBalance(address account, uint256 amount) external {
        _xpBalances[account] = amount;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _xpBalances[account];
    }
}

/// @notice Mock Uniswap V2 Router
contract MockRouter {
    function factory() external view returns (address) {
        return address(this);
    }

    function WETH() external pure returns (address) {
        return address(1);
    }

    function addLiquidity(
        address, /* tokenA */
        address, /* tokenB */
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256, /* amountAMin */
        uint256, /* amountBMin */
        address, /* to */
        uint256 /* deadline */
    ) external pure returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        return (amountADesired, amountBDesired, amountADesired);
    }
}

/// @notice Mock Uniswap V2 Factory
contract MockFactory {
    address public mockPair;

    constructor() {
        mockPair = address(new MockPair());
    }

    function getPair(
        address,
        /* tokenA */
        address /* tokenB */
    )
        external
        view
        returns (address)
    {
        return mockPair;
    }

    function createPair(
        address,
        /* tokenA */
        address /* tokenB */
    )
        external
        view
        returns (address)
    {
        return mockPair;
    }
}

/// @notice Mock Uniswap V2 Pair
contract MockPair is ERC20 {
    constructor() ERC20("LP Token", "LP") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _mint(to, amount);
        return true;
    }
}

/// @notice Mock App Fee Router
contract MockAppFeeRouter {
    function routeFees(
        uint256,
        /* appId */
        uint256 /* amount */
    )
        external {}

    function feeBps() external pure returns (uint256) {
        return 100; // 1%
    }

    function takeAndForwardFee(
        address,
        /* payer */
        uint256 /* fee */
    )
        external {}
}

/**
 * @title Curve Lifecycle Unit Tests
 * @notice TDD tests for AppBondingCurve state machine
 * @dev Tests PENDING, ACTIVE, GRADUATED states, deadline, and forceGraduate
 *
 * Key Requirements from Protocol Changes:
 * - States: PENDING, ACTIVE, GRADUATED, CANCELLED
 * - Activation window: activationTime = now + activationDelay
 * - Deadline: deadline = activationTime + maxDuration
 * - forceGraduate: If deadline reached, graduate with whatever raised
 * - sweepFees: Route fees to FeeCollector
 */
contract CurveLifecycleTest is Test {
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;
    MockRouter public router;
    MockFactory public factory;
    MockElataPoints public xp;
    MockAppFeeRouter public feeRouter;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public governance = makeAddr("governance");
    address public creator = makeAddr("creator");
    address public buyer = makeAddr("buyer");
    address public appFactory = makeAddr("appFactory");

    uint256 public constant APP_ID = 1;
    uint256 public constant TARGET_RAISED = 50_000 ether;
    uint256 public constant LP_LOCK_DURATION = 180 days;
    uint256 public constant SEED_ELTA = 1000 ether;
    uint256 public constant TOKEN_SUPPLY = 10_000_000 ether;

    // Events to test (future - when state machine is implemented)
    // event StateChanged(uint256 indexed appId, CurveState oldState, CurveState newState);
    // event CurveActivated(uint256 indexed appId, uint256 activationTime);
    // event DeadlineSet(uint256 indexed appId, uint256 deadline);
    // event ForceGraduated(uint256 indexed appId, uint256 totalRaised);
    // event FeesSwepted(uint256 indexed appId, uint256 amount, address indexed to);

    function setUp() public {
        // Deploy core contracts
        elta = new ELTA(treasury);
        router = new MockRouter();
        factory = new MockFactory();
        xp = new MockElataPoints();
        feeRouter = new MockAppFeeRouter();

        // Deploy app token
        appToken = new AppToken(
            "Test App",
            "TAPP",
            18,
            TOKEN_SUPPLY,
            creator,
            appFactory, // factory as admin
            governance,
            address(1), // appRewards
            address(1), // veRewards
            treasury
        );

        // Fund test accounts
        vm.prank(treasury);
        elta.transfer(buyer, 100_000 ether);
        vm.prank(treasury);
        elta.transfer(appFactory, 10_000 ether);

        // Give buyer XP for early access
        xp.setBalance(buyer, 1000 ether);
    }

    function _deployCurve() internal {
        // Mock router factory call
        vm.mockCall(address(router), abi.encodeWithSignature("factory()"), abi.encode(address(factory)));

        // Mock appFactory graduation callback
        vm.mockCall(
            appFactory,
            abi.encodeWithSignature("onAppGraduated(uint256,address,address,uint256,uint256,uint256)"),
            abi.encode()
        );

        curve = new AppBondingCurve(
            APP_ID,
            appFactory,
            elta,
            appToken,
            IUniswapV2Router02(address(router)),
            TARGET_RAISED,
            LP_LOCK_DURATION,
            creator,
            treasury,
            IAppFeeRouter(address(feeRouter)),
            IElataPoints(address(xp)),
            governance,
            1 hours, // activationDelay
            30 days, // maxDuration
            creator // creator
        );
    }

    function _initializeCurve() internal {
        _deployCurve();

        // Mint tokens to curve (appFactory has MINTER_ROLE from AppToken constructor)
        vm.prank(appFactory);
        appToken.mint(address(curve), TOKEN_SUPPLY);

        // Transfer seed ELTA to curve
        vm.prank(treasury);
        elta.transfer(address(curve), SEED_ELTA);

        // Initialize curve
        vm.prank(appFactory);
        curve.initializeCurve(SEED_ELTA, TOKEN_SUPPLY);
    }

    // =========== State Tests ===========

    function test_InitialStateIsPending() public {
        _deployCurve();
        // New curve should start in PENDING state
        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.PENDING));
        assertFalse(curve.graduated());
    }

    function test_BuyRevertedWhenPending() public {
        _initializeCurve();
        // While PENDING (not yet activated), buy should revert
        vm.startPrank(buyer);
        elta.approve(address(curve), 1000 ether);
        vm.expectRevert(AppBondingCurve.NotActive.selector);
        curve.buy(1000 ether, 0, address(0));
        vm.stopPrank();
    }

    function test_StateAfterInitialize() public {
        _initializeCurve();
        // After initialize, still PENDING (need to activate)
        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.PENDING));
        assertFalse(curve.graduated());
        assertGt(curve.reserveElta(), 0);
        assertGt(curve.reserveToken(), 0);
    }

    function test_ActivateTransitionsPendingToActive() public {
        _initializeCurve();

        // Warp past activation delay
        vm.warp(block.timestamp + 1 hours + 1);

        // Activate
        curve.activate();

        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.ACTIVE));
    }

    function test_CannotActivateBeforeDelay() public {
        _initializeCurve();

        // Try to activate immediately (before delay)
        vm.expectRevert(AppBondingCurve.TooEarlyToActivate.selector);
        curve.activate();
    }

    function test_CanBuyAfterActivation() public {
        _initializeCurve();

        // Activate
        vm.warp(block.timestamp + 1 hours + 1);
        curve.activate();

        // Now can buy
        vm.startPrank(buyer);
        elta.approve(address(curve), 2000 ether);
        uint256 tokensOut = curve.buy(1000 ether, 0, address(0));
        vm.stopPrank();

        assertGt(tokensOut, 0);
    }

    function test_CreatorCanCancel() public {
        _initializeCurve();

        // Creator cancels
        vm.prank(creator);
        curve.cancel();

        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.CANCELLED));
    }

    function test_NonCreatorCannotCancel() public {
        _initializeCurve();

        vm.expectRevert(AppBondingCurve.OnlyCreator.selector);
        vm.prank(buyer);
        curve.cancel();
    }

    function test_CannotCancelAfterActivation() public {
        _initializeCurve();

        // Activate
        vm.warp(block.timestamp + 1 hours + 1);
        curve.activate();

        // Try to cancel
        vm.expectRevert(AppBondingCurve.NotPending.selector);
        vm.prank(creator);
        curve.cancel();
    }

    function test_ForceGraduateAfterDeadline() public {
        _initializeCurve();

        // Warp past deadline (1 hour activation + 30 days max duration)
        vm.warp(block.timestamp + 1 hours + 30 days + 1);

        // Force graduate
        curve.forceGraduate();

        assertEq(uint256(curve.state()), uint256(AppBondingCurve.CurveState.GRADUATED));
        assertTrue(curve.graduated());
    }

    function test_CannotForceGraduateBeforeDeadline() public {
        _initializeCurve();

        // Try to force graduate before deadline
        vm.expectRevert(AppBondingCurve.DeadlineNotReached.selector);
        curve.forceGraduate();
    }

    /*
    function test_StateAfterGraduation() public {
        _initializeCurve();

        // Buy enough to graduate
        uint256 amountToBuy = TARGET_RAISED - SEED_ELTA + 1000 ether;

        vm.startPrank(buyer);
        elta.approve(address(curve), amountToBuy);

        // Buy in chunks if needed
        while (!curve.graduated()) {
            uint256 buyAmount = 10_000 ether;
            if (elta.balanceOf(buyer) < buyAmount) break;
            curve.buy(buyAmount, 0, address(0));
        }
        vm.stopPrank();

        assertTrue(curve.graduated());
    }
    */

    // =========== Activation Window Tests ===========

    // Note: These tests require more complex mock setup for the curve to accept buys
    // Keeping as documentation of expected behavior

    /*
    function test_ActivationWindowRespected() public {
        _initializeCurve();
        // Current implementation uses XP gating for early access
        // earlyBuyDuration controls when non-XP users can buy

        uint256 earlyDuration = curve.earlyBuyDuration();
        assertGt(earlyDuration, 0);

        // Users with XP can buy immediately
        vm.startPrank(buyer);
        elta.approve(address(curve), 1000 ether);
        curve.buy(1000 ether, 0, address(0));
        vm.stopPrank();
    }
    */

    function test_NonXPUserCannotBuyEarly() public {
        _initializeCurve();

        // Activate curve
        vm.warp(block.timestamp + 1 hours + 1);
        curve.activate();

        address noXpUser = makeAddr("noXpUser");
        vm.prank(treasury);
        elta.transfer(noXpUser, 10_000 ether);

        vm.startPrank(noXpUser);
        elta.approve(address(curve), 1000 ether);

        // Should revert with InsufficientXP during early period
        vm.expectRevert(AppBondingCurve.InsufficientXP.selector);
        curve.buy(1000 ether, 0, address(0));
        vm.stopPrank();
    }

    /*
    function test_NonXPUserCanBuyAfterEarlyPeriod() public {
        _initializeCurve();

        address noXpUser = makeAddr("noXpUser");
        vm.prank(treasury);
        elta.transfer(noXpUser, 10_000 ether);

        // Advance time past early period
        vm.warp(block.timestamp + curve.earlyBuyDuration() + 1);

        vm.startPrank(noXpUser);
        elta.approve(address(curve), 1000 ether);
        curve.buy(1000 ether, 0, address(0));
        vm.stopPrank();

        // Should succeed
        assertGt(appToken.balanceOf(noXpUser), 0);
    }
    */

    // =========== Fee Sweep Tests ===========

    // Note: Fee tests require more complex setup
    /*
    function test_FeesAccumulate() public {
        _initializeCurve();

        // Buy tokens (fees should accumulate)
        vm.startPrank(buyer);
        elta.approve(address(curve), 10_000 ether);
        curve.buy(10_000 ether, 0, address(0));
        vm.stopPrank();

        // Note: Current implementation routes fees through AppFeeRouter
        // New implementation should route to FeeCollector
    }
    */

    // =========== View Functions Tests ===========

    /*
    function test_GetCurrentPrice() public {
        _initializeCurve();

        uint256 price1 = curve.getCurrentPrice();
        assertGt(price1, 0);

        // Buy some tokens
        vm.startPrank(buyer);
        elta.approve(address(curve), 10_000 ether);
        curve.buy(10_000 ether, 0, address(0));
        vm.stopPrank();

        uint256 price2 = curve.getCurrentPrice();
        assertGt(price2, price1); // Price should increase after buy
    }
    */

    function test_GetTokensOut() public {
        _initializeCurve();

        uint256 tokensOut = curve.getTokensOut(1000 ether);
        assertGt(tokensOut, 0);
    }

    /*
    function test_GetCurveState() public {
        _initializeCurve();

        (uint256 resElta, uint256 resToken, uint256 target, bool isGraduated,,) = curve.getCurveState();

        assertGt(resElta, 0);
        assertGt(resToken, 0);
        assertEq(target, TARGET_RAISED);
        assertFalse(isGraduated);

        // Buy some tokens
        vm.startPrank(buyer);
        elta.approve(address(curve), 10_000 ether);
        curve.buy(10_000 ether, 0, address(0));
        vm.stopPrank();

        (uint256 newResElta,,,,,) = curve.getCurveState();
        assertGt(newResElta, resElta); // Reserve increased after buy
    }
    */

    // =========== Fuzz Tests ===========

    /*
    function testFuzz_BuyIncreasesPriceAndReserve(uint256 buyAmount) public {
        _initializeCurve();

        buyAmount = bound(buyAmount, 100 ether, 10_000 ether);

        uint256 priceBefore = curve.getCurrentPrice();
        (uint256 reserveBefore,,,,,) = curve.getCurveState();

        vm.startPrank(buyer);
        elta.approve(address(curve), buyAmount);
        curve.buy(buyAmount, 0, address(0));
        vm.stopPrank();

        assertGt(curve.getCurrentPrice(), priceBefore);
        (uint256 reserveAfter,,,,,) = curve.getCurveState();
        assertGt(reserveAfter, reserveBefore);
    }
    */
}
