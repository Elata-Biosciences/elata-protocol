// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {ELTA} from "../../src/token/ELTA.sol";
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

/// @notice Mock FeeManager for testing sweepElta
/// @dev Implements depositEltaForApp to receive ELTA from FeeCollector
contract MockFeeManager {
    ERC20 public elta;
    mapping(uint256 => uint256) public pendingEltaToDistribute;

    constructor(address _elta) {
        elta = ERC20(_elta);
    }

    function depositEltaForApp(uint256 appId, uint256 amount) external {
        elta.transferFrom(msg.sender, address(this), amount);
        pendingEltaToDistribute[appId] += amount;
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
    MockFeeManager public mockFeeManager;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public feeSwapper = makeAddr("feeSwapper");
    address public appFactory = makeAddr("appFactory");
    address public user = makeAddr("user");

    uint256 public constant APP_ID_1 = 1;
    uint256 public constant APP_ID_2 = 2;

    // Events to test
    event EltaDeposited(uint256 indexed appId, uint256 amount, address indexed from);
    event AppTokenDeposited(uint256 indexed appId, address indexed token, uint256 amount, address indexed from);
    event EltaSwept(uint256 indexed appId, uint256 amount, address indexed to);
    event AppTokenSwept(uint256 indexed appId, address indexed token, uint256 amount, address indexed to);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);
    event FeeSwapperUpdated(address indexed oldFeeSwapper, address indexed newFeeSwapper);

    function setUp() public {
        // Deploy tokens
        elta = new ELTA(treasury);
        appToken1 = new MockAppToken();
        appToken2 = new MockAppToken();

        // Deploy MockFeeManager
        mockFeeManager = new MockFeeManager(address(elta));

        // Deploy FeeCollector
        collector = new FeeCollector(address(elta), admin, address(mockFeeManager), feeSwapper);

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
        assertEq(collector.feeManager(), address(mockFeeManager));
        assertEq(collector.feeSwapper(), feeSwapper);
    }

    function test_RevertWhen_DeployWithZeroELTA() public {
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        new FeeCollector(address(0), admin, address(mockFeeManager), feeSwapper);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        new FeeCollector(address(elta), address(0), address(mockFeeManager), feeSwapper);
    }

    // =========== ELTA Deposit Tests ===========

    function test_DepositElta() public {
        uint256 amount = 1000 ether;

        vm.startPrank(user);
        elta.approve(address(collector), amount);

        vm.expectEmit(true, true, true, true);
        emit EltaDeposited(APP_ID_1, amount, user);
        collector.depositElta(APP_ID_1, amount);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1), amount);
        assertEq(elta.balanceOf(address(collector)), amount);
    }

    function test_DepositEltaMultipleTimes() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;

        vm.startPrank(user);
        elta.approve(address(collector), amount1 + amount2);

        collector.depositElta(APP_ID_1, amount1);
        collector.depositElta(APP_ID_1, amount2);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1), amount1 + amount2);
    }

    function test_DepositEltaForDifferentApps() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;

        vm.startPrank(user);
        elta.approve(address(collector), amount1 + amount2);

        collector.depositElta(APP_ID_1, amount1);
        collector.depositElta(APP_ID_2, amount2);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1), amount1);
        assertEq(collector.pendingEltaFees(APP_ID_2), amount2);
    }

    function test_RevertWhen_DepositZeroElta() public {
        vm.prank(user);
        vm.expectRevert(FeeCollector.InvalidAmount.selector);
        collector.depositElta(APP_ID_1, 0);
    }

    // =========== App Token Deposit Tests ===========

    function test_DepositAppToken() public {
        uint256 amount = 1000 ether;

        vm.startPrank(user);
        appToken1.approve(address(collector), amount);

        vm.expectEmit(true, true, true, true);
        emit AppTokenDeposited(APP_ID_1, address(appToken1), amount, user);
        collector.depositAppToken(APP_ID_1, address(appToken1), amount);
        vm.stopPrank();

        assertEq(collector.pendingAppTokenFees(APP_ID_1, address(appToken1)), amount);
        assertEq(appToken1.balanceOf(address(collector)), amount);
    }

    function test_DepositMultipleAppTokens() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 700 ether;

        vm.startPrank(user);
        appToken1.approve(address(collector), amount1);
        appToken2.approve(address(collector), amount2);

        collector.depositAppToken(APP_ID_1, address(appToken1), amount1);
        collector.depositAppToken(APP_ID_1, address(appToken2), amount2);
        vm.stopPrank();

        assertEq(collector.pendingAppTokenFees(APP_ID_1, address(appToken1)), amount1);
        assertEq(collector.pendingAppTokenFees(APP_ID_1, address(appToken2)), amount2);
    }

    function test_RevertWhen_DepositZeroAppToken() public {
        vm.prank(user);
        vm.expectRevert(FeeCollector.InvalidAmount.selector);
        collector.depositAppToken(APP_ID_1, address(appToken1), 0);
    }

    function test_RevertWhen_DepositAppTokenWithZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        collector.depositAppToken(APP_ID_1, address(0), 1000 ether);
    }

    // =========== Sweep ELTA Tests ===========

    function test_SweepElta() public {
        uint256 amount = 1000 ether;

        // Deposit first
        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, amount);
        vm.stopPrank();

        // Sweep - permissionless
        vm.expectEmit(true, true, true, true);
        emit EltaSwept(APP_ID_1, amount, address(mockFeeManager));
        collector.sweepElta(APP_ID_1);

        assertEq(collector.pendingEltaFees(APP_ID_1), 0);
        assertEq(elta.balanceOf(address(mockFeeManager)), amount);
        assertEq(mockFeeManager.pendingEltaToDistribute(APP_ID_1), amount);
    }

    function test_SweepEltaIsPermissionless() public {
        uint256 amount = 1000 ether;

        // Deposit first
        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, amount);
        vm.stopPrank();

        // Anyone can sweep
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        collector.sweepElta(APP_ID_1);

        assertEq(elta.balanceOf(address(mockFeeManager)), amount);
    }

    function test_RevertWhen_SweepEltaWithNothingPending() public {
        vm.expectRevert(FeeCollector.NothingToSweep.selector);
        collector.sweepElta(APP_ID_1);
    }

    // =========== Sweep App Token Tests ===========

    function test_SweepAppToken() public {
        uint256 amount = 1000 ether;

        // Deposit first
        vm.startPrank(user);
        appToken1.approve(address(collector), amount);
        collector.depositAppToken(APP_ID_1, address(appToken1), amount);
        vm.stopPrank();

        // Sweep - goes to FeeSwapper
        vm.expectEmit(true, true, true, true);
        emit AppTokenSwept(APP_ID_1, address(appToken1), amount, feeSwapper);
        collector.sweepAppToken(APP_ID_1, address(appToken1));

        assertEq(collector.pendingAppTokenFees(APP_ID_1, address(appToken1)), 0);
        assertEq(appToken1.balanceOf(feeSwapper), amount);
    }

    function test_SweepAppTokenIsPermissionless() public {
        uint256 amount = 1000 ether;

        // Deposit first
        vm.startPrank(user);
        appToken1.approve(address(collector), amount);
        collector.depositAppToken(APP_ID_1, address(appToken1), amount);
        vm.stopPrank();

        // Anyone can sweep
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        collector.sweepAppToken(APP_ID_1, address(appToken1));

        assertEq(appToken1.balanceOf(feeSwapper), amount);
    }

    function test_RevertWhen_SweepAppTokenWithNothingPending() public {
        vm.expectRevert(FeeCollector.NothingToSweep.selector);
        collector.sweepAppToken(APP_ID_1, address(appToken1));
    }

    // =========== Admin Tests ===========

    function test_UpdateFeeManager() public {
        address newFeeManager = makeAddr("newFeeManager");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit FeeManagerUpdated(address(mockFeeManager), newFeeManager);
        collector.setFeeManager(newFeeManager);

        assertEq(collector.feeManager(), newFeeManager);
    }

    function test_UpdateFeeSwapper() public {
        address newFeeSwapper = makeAddr("newFeeSwapper");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit FeeSwapperUpdated(feeSwapper, newFeeSwapper);
        collector.setFeeSwapper(newFeeSwapper);

        assertEq(collector.feeSwapper(), newFeeSwapper);
    }

    function test_RevertWhen_NonAdminUpdatesFeeManager() public {
        vm.prank(user);
        vm.expectRevert(FeeCollector.OnlyAdmin.selector);
        collector.setFeeManager(makeAddr("newFeeManager"));
    }

    function test_RevertWhen_SetFeeManagerToZero() public {
        vm.prank(admin);
        vm.expectRevert(FeeCollector.ZeroAddress.selector);
        collector.setFeeManager(address(0));
    }

    // =========== View Functions Tests ===========

    function test_GetTotalPendingElta() public {
        vm.startPrank(user);
        elta.approve(address(collector), 2000 ether);
        collector.depositElta(APP_ID_1, 500 ether);
        collector.depositElta(APP_ID_2, 700 ether);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1), 500 ether);
        assertEq(collector.pendingEltaFees(APP_ID_2), 700 ether);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_DepositElta(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);

        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, amount);
        vm.stopPrank();

        assertEq(collector.pendingEltaFees(APP_ID_1), amount);
    }

    function testFuzz_DepositAndSweepElta(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);

        vm.startPrank(user);
        elta.approve(address(collector), amount);
        collector.depositElta(APP_ID_1, amount);
        vm.stopPrank();

        collector.sweepElta(APP_ID_1);

        assertEq(collector.pendingEltaFees(APP_ID_1), 0);
        assertEq(elta.balanceOf(address(mockFeeManager)), amount);
    }

    function testFuzz_DepositAppToken(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);

        vm.startPrank(user);
        appToken1.approve(address(collector), amount);
        collector.depositAppToken(APP_ID_1, address(appToken1), amount);
        vm.stopPrank();

        assertEq(collector.pendingAppTokenFees(APP_ID_1, address(appToken1)), amount);
    }
}
