// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {ELTA} from "elta/ELTA.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock app token for testing
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App Token", "MAPP") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock FeeRouterV2 for testing FeeCollector sweeps
contract MockFeeRouterV2 {
    mapping(uint256 => mapping(FeeKind => mapping(address => uint256))) public accrued;

    function accrue(uint256 appId, FeeKind kind, address asset, uint256 amount, address) external {
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        accrued[appId][kind][asset] += amount;
    }
}

/**
 * @title FeeCollector Unit Tests
 * @notice TDD tests for FeeCollector - the single sink for protocol fee assets
 * @dev Tests per-app accounting, deposit, and sweep functionality
 */
contract FeeCollectorTest is Test {
    FeeCollector public collector;
    ELTA public elta;
    MockAppToken public appToken1;
    MockAppToken public appToken2;
    MockFeeRouterV2 public mockFeeRouter;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public feeSwapper = makeAddr("feeSwapper");
    address public appFactory = makeAddr("appFactory");
    address public user = makeAddr("user");

    uint256 public constant APP_ID_1 = 1;
    uint256 public constant APP_ID_2 = 2;

    // Events to test
    event EltaDeposited(uint256 indexed appId, FeeKind indexed kind, uint256 amount, address indexed from);
    event AppTokenDeposited(
        uint256 indexed appId, FeeKind indexed kind, address indexed token, uint256 amount, address from
    );
    event EltaSwept(uint256 indexed appId, FeeKind indexed kind, uint256 amount, address indexed to, address sweeper);
    event AppTokenSwept(
        uint256 indexed appId, FeeKind indexed kind, address indexed token, uint256 amount, address to, address sweeper
    );
    event FeeRouterUpdated(address indexed oldFeeRouter, address indexed newFeeRouter);
    event FeeSwapperUpdated(address indexed oldFeeSwapper, address indexed newFeeSwapper);

    function setUp() public {
        // Deploy tokens
        elta = new ELTA(treasury);
        appToken1 = new MockAppToken();
        appToken2 = new MockAppToken();

        // Deploy Mock FeeRouterV2
        mockFeeRouter = new MockFeeRouterV2();

        // Deploy FeeCollector
        collector = new FeeCollector(address(elta), admin, address(mockFeeRouter), feeSwapper);

        // Distribute tokens for testing
        vm.prank(treasury);
        elta.transfer(user, 100_000 ether);
        appToken1.transfer(user, 100_000 ether);
        appToken2.transfer(user, 100_000 ether);
    }

    // =========== Deployment Tests ===========

    function test_Deployment() public view {
        assertEq(address(collector.ELTA()), address(elta));
        assertEq(collector.admin(), admin);
        assertEq(collector.feeRouter(), address(mockFeeRouter));
        assertEq(collector.feeSwapper(), feeSwapper);
    }

    function test_RevertWhen_DeployWithZeroELTA() public {
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        new FeeCollector(address(0), admin, address(mockFeeRouter), feeSwapper);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        new FeeCollector(address(elta), address(0), address(mockFeeRouter), feeSwapper);
    }

    // =========== ELTA Deposit Tests ===========

    function test_DepositElta() public {
        uint256 amount = 1000 ether;
        FeeKind kind = FeeKind.TRADING_FEE;

        vm.startPrank(user);
        elta.approve(address(collector), amount);

        vm.expectEmit(true, true, true, true);
        emit EltaDeposited(APP_ID_1, kind, amount, user);
        collector.depositElta(APP_ID_1, kind, amount);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), amount);
        assertEq(elta.balanceOf(address(collector)), amount);
    }

    function test_DepositEltaMultipleTimes() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;
        FeeKind kind = FeeKind.TRADING_FEE;

        vm.startPrank(user);
        elta.approve(address(collector), amount1 + amount2);

        collector.depositElta(APP_ID_1, kind, amount1);
        collector.depositElta(APP_ID_1, kind, amount2);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), amount1 + amount2);
    }

    function test_DepositEltaForDifferentApps() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;
        FeeKind kind = FeeKind.TRADING_FEE;

        vm.startPrank(user);
        elta.approve(address(collector), amount1 + amount2);

        collector.depositElta(APP_ID_1, kind, amount1);
        collector.depositElta(APP_ID_2, kind, amount2);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), amount1);
        assertEq(collector.pendingEltaFees(APP_ID_2, kind), amount2);
    }

    function test_RevertWhen_DepositZeroElta() public {
        FeeKind kind = FeeKind.TRADING_FEE;
        vm.prank(user);
        vm.expectRevert(FeeCollector.InvalidAmount.selector);
        collector.depositElta(APP_ID_1, kind, 0);
    }

    // =========== App Token Deposit Tests ===========

    function test_DepositAppToken() public {
        uint256 amount = 1000 ether;
        FeeKind kind = FeeKind.TRANSFER_TAX;

        vm.startPrank(user);
        appToken1.approve(address(collector), amount);

        vm.expectEmit(true, true, true, true);
        emit AppTokenDeposited(APP_ID_1, kind, address(appToken1), amount, user);
        collector.depositAppToken(APP_ID_1, kind, address(appToken1), amount);
        vm.stopPrank();

        assertEq(collector.pendingAppTokenFees(APP_ID_1, kind, address(appToken1)), amount);
        assertEq(appToken1.balanceOf(address(collector)), amount);
    }

    function test_DepositMultipleAppTokens() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 700 ether;
        FeeKind kind = FeeKind.TRANSFER_TAX;

        vm.startPrank(user);
        appToken1.approve(address(collector), amount1);
        appToken2.approve(address(collector), amount2);

        collector.depositAppToken(APP_ID_1, kind, address(appToken1), amount1);
        collector.depositAppToken(APP_ID_1, kind, address(appToken2), amount2);
        vm.stopPrank();

        assertEq(collector.pendingAppTokenFees(APP_ID_1, kind, address(appToken1)), amount1);
        assertEq(collector.pendingAppTokenFees(APP_ID_1, kind, address(appToken2)), amount2);
    }

    function test_RevertWhen_DepositZeroAppToken() public {
        FeeKind kind = FeeKind.TRANSFER_TAX;
        vm.prank(user);
        vm.expectRevert(FeeCollector.InvalidAmount.selector);
        collector.depositAppToken(APP_ID_1, kind, address(appToken1), 0);
    }

    function test_RevertWhen_DepositAppTokenWithZeroAddress() public {
        FeeKind kind = FeeKind.TRANSFER_TAX;
        vm.prank(user);
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        collector.depositAppToken(APP_ID_1, kind, address(0), 1000 ether);
    }

    // =========== Sweep ELTA Tests ===========

    function test_SweepElta() public {
        uint256 amount = 1000 ether;
        FeeKind kind = FeeKind.TRADING_FEE;

        // Deposit first
        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, kind, amount);
        vm.stopPrank();

        // Sweep - permissionless
        vm.expectEmit(true, true, true, true);
        emit EltaSwept(APP_ID_1, kind, amount, address(mockFeeRouter), address(this));
        collector.sweepElta(APP_ID_1, kind);

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), 0);
        assertEq(elta.balanceOf(address(mockFeeRouter)), amount);
        assertEq(mockFeeRouter.accrued(APP_ID_1, kind, address(elta)), amount);
    }

    function test_SweepEltaIsPermissionless() public {
        uint256 amount = 1000 ether;
        FeeKind kind = FeeKind.TRADING_FEE;

        // Deposit first
        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, kind, amount);
        vm.stopPrank();

        // Anyone can sweep
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        collector.sweepElta(APP_ID_1, kind);

        assertEq(elta.balanceOf(address(mockFeeRouter)), amount);
    }

    function test_RevertWhen_SweepEltaWithNothingPending() public {
        FeeKind kind = FeeKind.TRADING_FEE;
        vm.expectRevert(FeeCollector.NothingToSweep.selector);
        collector.sweepElta(APP_ID_1, kind);
    }

    // =========== Sweep App Token Tests ===========

    function test_SweepAppToken() public {
        uint256 amount = 1000 ether;
        FeeKind kind = FeeKind.TRANSFER_TAX;

        // Deposit first
        vm.startPrank(user);
        appToken1.approve(address(collector), amount);
        collector.depositAppToken(APP_ID_1, kind, address(appToken1), amount);
        vm.stopPrank();

        // Sweep - goes to FeeSwapper
        vm.expectEmit(true, true, true, true);
        emit AppTokenSwept(APP_ID_1, kind, address(appToken1), amount, address(mockFeeRouter), address(this));
        collector.sweepAppToken(APP_ID_1, kind, address(appToken1));

        assertEq(collector.pendingAppTokenFees(APP_ID_1, kind, address(appToken1)), 0);
        assertEq(appToken1.balanceOf(address(mockFeeRouter)), amount);
    }

    function test_SweepAppTokenIsPermissionless() public {
        uint256 amount = 1000 ether;
        FeeKind kind = FeeKind.TRANSFER_TAX;

        // Deposit first
        vm.startPrank(user);
        appToken1.approve(address(collector), amount);
        collector.depositAppToken(APP_ID_1, kind, address(appToken1), amount);
        vm.stopPrank();

        // Anyone can sweep
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        collector.sweepAppToken(APP_ID_1, kind, address(appToken1));

        assertEq(appToken1.balanceOf(address(mockFeeRouter)), amount);
    }

    function test_RevertWhen_SweepAppTokenWithNothingPending() public {
        FeeKind kind = FeeKind.TRANSFER_TAX;
        vm.expectRevert(FeeCollector.NothingToSweep.selector);
        collector.sweepAppToken(APP_ID_1, kind, address(appToken1));
    }

    // =========== Admin Tests ===========

    function test_UpdateFeeRouter() public {
        address newFeeRouter = makeAddr("newFeeRouter");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit FeeRouterUpdated(address(mockFeeRouter), newFeeRouter);
        collector.setFeeRouter(newFeeRouter);

        assertEq(collector.feeRouter(), newFeeRouter);
    }

    function test_UpdateFeeSwapper() public {
        address newFeeSwapper = makeAddr("newFeeSwapper");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit FeeSwapperUpdated(feeSwapper, newFeeSwapper);
        collector.setFeeSwapper(newFeeSwapper);

        assertEq(collector.feeSwapper(), newFeeSwapper);
    }

    function test_RevertWhen_NonAdminUpdatesFeeRouter() public {
        vm.prank(user);
        vm.expectRevert(FeeCollector.OnlyAdmin.selector);
        collector.setFeeRouter(makeAddr("newFeeRouter"));
    }

    function test_RevertWhen_SetFeeRouterToZero() public {
        vm.prank(admin);
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        collector.setFeeRouter(address(0));
    }

    // =========== View Functions Tests ===========

    function test_GetTotalPendingElta() public {
        FeeKind kind = FeeKind.TRADING_FEE;
        vm.startPrank(user);
        elta.approve(address(collector), 2000 ether);
        collector.depositElta(APP_ID_1, kind, 500 ether);
        collector.depositElta(APP_ID_2, kind, 700 ether);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), 500 ether);
        assertEq(collector.pendingEltaFees(APP_ID_2, kind), 700 ether);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_DepositElta(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);
        FeeKind kind = FeeKind.TRADING_FEE;

        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, kind, amount);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), amount);
    }

    function testFuzz_DepositAndSweepElta(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);
        FeeKind kind = FeeKind.TRADING_FEE;

        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, kind, amount);
        vm.stopPrank();

        collector.sweepElta(APP_ID_1, kind);

        assertEq(collector.pendingEltaFees(APP_ID_1, kind), 0);
        assertEq(elta.balanceOf(address(mockFeeRouter)), amount);
    }

    function testFuzz_DepositAppToken(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);
        FeeKind kind = FeeKind.TRANSFER_TAX;

        vm.startPrank(user);
        appToken1.approve(address(collector), amount);
        collector.depositAppToken(APP_ID_1, kind, address(appToken1), amount);
        vm.stopPrank();

        assertEq(collector.pendingAppTokenFees(APP_ID_1, kind, address(appToken1)), amount);
    }
}
