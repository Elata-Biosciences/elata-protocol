// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @notice Mock App Token for swap testing
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App", "MAPP") {
        _mint(msg.sender, 100_000_000 ether);
    }
}

/**
 * @title FeePipelineSecurity
 * @notice Red team security tests for FeeCollector, FeeSwapper, FeeManager
 */
contract FeePipelineSecurity is Test {
    ELTA public elta;
    MockUSDC public usdc;
    MockAppToken public appToken;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    FeeSwapper public feeSwapper;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public appRewardsDistributor = makeAddr("appRewardsDistributor");
    address public veRewardsDistributor = makeAddr("veRewardsDistributor");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy tokens
        vm.prank(admin);
        elta = new ELTA(admin);
        usdc = new MockUSDC();
        appToken = new MockAppToken();

        // Deploy FeeSwapper (with temporary feeManager address, will update later)
        feeSwapper = new FeeSwapper(address(elta), admin, governance, address(0));

        // Deploy FeeManager
        feeManager = new FeeManager(
            address(elta),
            address(usdc),
            admin,
            governance,
            appRewardsDistributor,
            veRewardsDistributor,
            treasury,
            1 days
        );

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(feeManager), address(feeSwapper));

        // Connect components
        vm.prank(admin);
        feeManager.setDepositor(address(feeCollector), true);

        // Update FeeSwapper's feeManager
        vm.prank(admin);
        feeSwapper.setFeeManager(address(feeManager));

        // Fund attacker
        vm.prank(admin);
        elta.transfer(attacker, 100_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTOR SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotDepositZeroAmount() public {
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);

        vm.expectRevert(FeeCollector.InvalidAmount.selector);
        feeCollector.depositElta(0, 0);
        vm.stopPrank();
    }

    function test_Security_UnauthorizedSweep() public {
        // Deposit some fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        // Sweep is permissionless, but funds go to feeManager
        uint256 managerBefore = elta.balanceOf(address(feeManager));
        feeCollector.sweepElta(0);
        uint256 managerAfter = elta.balanceOf(address(feeManager));

        // Funds should go to manager, not attacker
        assertGt(managerAfter, managerBefore, "Funds should go to manager");
    }

    function test_Security_CannotExtractFundsDirectly() public {
        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        // Try to withdraw directly (no such function)
        // FeeCollector has no withdraw function - funds only go via sweep
        uint256 collectorBalance = elta.balanceOf(address(feeCollector));
        assertEq(collectorBalance, 1000 ether, "Funds should be in collector");
    }

    function test_Security_DoubleDepositAccounting() public {
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 2000 ether);

        // Deposit twice
        feeCollector.depositElta(0, 500 ether);
        feeCollector.depositElta(0, 500 ether);

        // Check accounting
        uint256 pending = feeCollector.pendingEltaFees(0);
        assertEq(pending, 1000 ether, "Should track both deposits");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE SWAPPER SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAdminCanSetFeeManager() public {
        vm.expectRevert(FeeSwapper.OnlyAdmin.selector);
        vm.prank(attacker);
        feeSwapper.setFeeManager(attacker);
    }

    function test_Security_OnlyGovernanceCanSetRouter() public {
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        vm.prank(attacker);
        feeSwapper.setRouterAllowed(attacker, true);
    }

    function test_Security_CannotSwapWithUnallowedRouter() public {
        // Fund swapper - use the deployer who has tokens
        appToken.transfer(address(feeSwapper), 1000 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Try to swap with unallowed router
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        feeSwapper.swapFromBalance(0, address(appToken), 100 ether, 0, attacker, path);
    }

    function test_Security_SwapperMinThresholdEnforced() public {
        // Set high threshold
        vm.prank(governance);
        feeSwapper.setMinSwapThreshold(100 ether);

        // Fund swapper - deployer has tokens
        appToken.transfer(address(feeSwapper), 1000 ether);

        // Allow a router
        vm.prank(governance);
        feeSwapper.setRouterAllowed(makeAddr("router"), true);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Try to swap below threshold
        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        feeSwapper.swapFromBalance(0, address(appToken), 10 ether, 0, makeAddr("router"), path);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE MANAGER SECURITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyDepositorCanDeposit() public {
        vm.startPrank(attacker);
        elta.approve(address(feeManager), 1000 ether);

        vm.expectRevert(FeeManager.OnlyDepositor.selector);
        feeManager.depositEltaForApp(0, 1000 ether);
        vm.stopPrank();
    }

    function test_Security_CannotCloseEpochEarly() public {
        // Deposit via collector/sweep
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(0);

        // Try to close epoch immediately (should fail - epoch not ended)
        vm.expectRevert(FeeManager.EpochNotEnded.selector);
        feeManager.closeEpoch(0);
    }

    function test_Security_EpochClosesAfterDelay() public {
        // Deposit via collector/sweep
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(0);

        // Warp past epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Now should work
        feeManager.closeEpoch(0);
    }

    function test_Security_CannotDoubleCloseEpoch() public {
        // Setup and deposit
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 2000 ether);
        feeCollector.depositElta(0, 1000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(0);

        // Close first epoch
        vm.warp(block.timestamp + 1 days + 1);
        feeManager.closeEpoch(0);

        // Second close should fail - either EpochNotEnded (if epoch resets) or NothingToDistribute
        vm.expectRevert(); // Generic revert, either error is acceptable
        feeManager.closeEpoch(0);
    }

    function test_Security_FeeSplitsSumTo100() public {
        (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury_, uint256 referral) =
            feeManager.feeSplits();

        assertEq(appStakers + veElta + creator + treasury_ + referral, 10000, "Fee splits must sum to 10000 bps");
    }

    function test_Security_CannotSetInvalidFeeSplits() public {
        // Try to set splits that exceed 100%
        vm.expectRevert(FeeManager.InvalidFeeSplits.selector);
        vm.prank(governance);
        feeManager.setFeeSplits(5000, 5000, 5000, 0, 0); // 150%
    }

    function test_Security_OnlyGovernanceCanSetSplits() public {
        vm.expectRevert(FeeManager.OnlyGovernance.selector);
        vm.prank(attacker);
        feeManager.setFeeSplits(2500, 2500, 2500, 2500, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_DepositAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 50_000 ether);

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(0, amount);
        vm.stopPrank();

        uint256 pending = feeCollector.pendingEltaFees(0);
        assertEq(pending, amount, "Pending should match deposit");
    }

    function testFuzz_Security_MultipleAppDeposits(uint256 appId1, uint256 appId2, uint256 amount1, uint256 amount2)
        public
    {
        appId1 = bound(appId1, 0, 100);
        appId2 = bound(appId2, 0, 100);
        amount1 = bound(amount1, 1 ether, 25_000 ether);
        amount2 = bound(amount2, 1 ether, 25_000 ether);

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), amount1 + amount2);

        feeCollector.depositElta(appId1, amount1);
        feeCollector.depositElta(appId2, amount2);
        vm.stopPrank();

        // Verify per-app accounting
        if (appId1 == appId2) {
            assertEq(feeCollector.pendingEltaFees(appId1), amount1 + amount2, "Same app should sum");
        } else {
            assertEq(feeCollector.pendingEltaFees(appId1), amount1, "App 1 amount correct");
            assertEq(feeCollector.pendingEltaFees(appId2), amount2, "App 2 amount correct");
        }
    }
}
