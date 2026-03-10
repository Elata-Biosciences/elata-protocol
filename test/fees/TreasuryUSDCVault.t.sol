// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryUSDCVault} from "../../src/fees/TreasuryUSDCVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 100_000_000e6); // USDC has 6 decimals
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TreasuryUSDCVault Unit Tests
 * @notice TDD tests for TreasuryUSDCVault - simple USDC custody with clean accounting
 * @dev Tests deposit, withdrawal, and event emission
 */
contract TreasuryUSDCVaultTest is Test {
    TreasuryUSDCVault public vault;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public treasuryMultisig = makeAddr("treasuryMultisig");
    address public feeManager = makeAddr("feeManager");
    address public user = makeAddr("user");

    uint256 public constant APP_ID_1 = 1;
    uint256 public constant APP_ID_2 = 2;

    // Events to test
    event TreasuryRevenue(uint256 indexed appId, uint256 usdcAmount, uint256 indexed epochId);
    event Withdrawal(address indexed to, uint256 amount, address indexed caller);
    event TreasuryMultisigUpdated(address indexed oldMultisig, address indexed newMultisig);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new TreasuryUSDCVault(address(usdc), admin, treasuryMultisig, feeManager);

        // Give feeManager some USDC to deposit
        usdc.transfer(feeManager, 10_000_000e6);
    }

    // =========== Deployment Tests ===========

    function test_Deployment() public view {
        assertEq(address(vault.USDC()), address(usdc));
        assertEq(vault.admin(), admin);
        assertEq(vault.treasuryMultisig(), treasuryMultisig);
        assertEq(vault.feeManager(), feeManager);
    }

    function test_RevertWhen_DeployWithZeroUSDC() public {
        vm.expectRevert(TreasuryUSDCVault.ZeroAddress.selector);
        new TreasuryUSDCVault(address(0), admin, treasuryMultisig, feeManager);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(TreasuryUSDCVault.ZeroAddress.selector);
        new TreasuryUSDCVault(address(usdc), address(0), treasuryMultisig, feeManager);
    }

    function test_RevertWhen_DeployWithZeroTreasury() public {
        vm.expectRevert(TreasuryUSDCVault.ZeroAddress.selector);
        new TreasuryUSDCVault(address(usdc), admin, address(0), feeManager);
    }

    // =========== Deposit Tests ===========

    function test_Deposit() public {
        uint256 amount = 10_000e6;
        uint256 epochId = 1;

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount);

        vm.expectEmit(true, true, true, true);
        emit TreasuryRevenue(APP_ID_1, amount, epochId);
        vault.deposit(APP_ID_1, amount, epochId);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(vault)), amount);
        assertEq(vault.totalRevenue(), amount);
        assertEq(vault.revenueByApp(APP_ID_1), amount);
        assertEq(vault.revenueByEpoch(epochId), amount);
    }

    function test_DepositMultipleTimes() public {
        uint256 amount1 = 5_000e6;
        uint256 amount2 = 3_000e6;
        uint256 epochId = 1;

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount1 + amount2);

        vault.deposit(APP_ID_1, amount1, epochId);
        vault.deposit(APP_ID_1, amount2, epochId);
        vm.stopPrank();

        assertEq(vault.totalRevenue(), amount1 + amount2);
        assertEq(vault.revenueByApp(APP_ID_1), amount1 + amount2);
    }

    function test_DepositFromDifferentApps() public {
        uint256 amount1 = 5_000e6;
        uint256 amount2 = 3_000e6;
        uint256 epochId = 1;

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount1 + amount2);

        vault.deposit(APP_ID_1, amount1, epochId);
        vault.deposit(APP_ID_2, amount2, epochId);
        vm.stopPrank();

        assertEq(vault.totalRevenue(), amount1 + amount2);
        assertEq(vault.revenueByApp(APP_ID_1), amount1);
        assertEq(vault.revenueByApp(APP_ID_2), amount2);
    }

    function test_DepositInDifferentEpochs() public {
        uint256 amount1 = 5_000e6;
        uint256 amount2 = 3_000e6;

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount1 + amount2);

        vault.deposit(APP_ID_1, amount1, 1);
        vault.deposit(APP_ID_1, amount2, 2);
        vm.stopPrank();

        assertEq(vault.revenueByEpoch(1), amount1);
        assertEq(vault.revenueByEpoch(2), amount2);
    }

    function test_RevertWhen_DepositZeroAmount() public {
        vm.prank(feeManager);
        vm.expectRevert(TreasuryUSDCVault.InvalidAmount.selector);
        vault.deposit(APP_ID_1, 0, 1);
    }

    function test_RevertWhen_NonFeeManagerDeposits() public {
        vm.prank(user);
        vm.expectRevert(TreasuryUSDCVault.OnlyFeeManager.selector);
        vault.deposit(APP_ID_1, 1000e6, 1);
    }

    // =========== Withdrawal Tests ===========

    function test_Withdraw() public {
        uint256 depositAmount = 10_000e6;
        uint256 withdrawAmount = 5_000e6;

        // Deposit first
        vm.startPrank(feeManager);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(APP_ID_1, depositAmount, 1);
        vm.stopPrank();

        // Withdraw
        vm.prank(treasuryMultisig);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(treasuryMultisig, withdrawAmount, treasuryMultisig);
        vault.withdraw(withdrawAmount);

        assertEq(usdc.balanceOf(treasuryMultisig), withdrawAmount);
        assertEq(usdc.balanceOf(address(vault)), depositAmount - withdrawAmount);
    }

    function test_WithdrawAll() public {
        uint256 depositAmount = 10_000e6;

        // Deposit first
        vm.startPrank(feeManager);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(APP_ID_1, depositAmount, 1);
        vm.stopPrank();

        // Withdraw all
        vm.prank(treasuryMultisig);
        vault.withdraw(depositAmount);

        assertEq(usdc.balanceOf(treasuryMultisig), depositAmount);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_RevertWhen_NonTreasuryWithdraws() public {
        uint256 depositAmount = 10_000e6;

        // Deposit first
        vm.startPrank(feeManager);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(APP_ID_1, depositAmount, 1);
        vm.stopPrank();

        // Try to withdraw as non-treasury
        vm.prank(user);
        vm.expectRevert(TreasuryUSDCVault.OnlyTreasury.selector);
        vault.withdraw(5_000e6);
    }

    function test_RevertWhen_WithdrawZeroAmount() public {
        vm.prank(treasuryMultisig);
        vm.expectRevert(TreasuryUSDCVault.InvalidAmount.selector);
        vault.withdraw(0);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        uint256 depositAmount = 10_000e6;

        // Deposit first
        vm.startPrank(feeManager);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(APP_ID_1, depositAmount, 1);
        vm.stopPrank();

        // Try to withdraw more than balance
        vm.prank(treasuryMultisig);
        vm.expectRevert(TreasuryUSDCVault.InsufficientBalance.selector);
        vault.withdraw(depositAmount + 1);
    }

    // =========== Admin Tests ===========

    function test_UpdateTreasuryMultisig() public {
        address newMultisig = makeAddr("newMultisig");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit TreasuryMultisigUpdated(treasuryMultisig, newMultisig);
        vault.setTreasuryMultisig(newMultisig);

        assertEq(vault.treasuryMultisig(), newMultisig);
    }

    function test_UpdateFeeManager() public {
        address newFeeManager = makeAddr("newFeeManager");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit FeeManagerUpdated(feeManager, newFeeManager);
        vault.setFeeManager(newFeeManager);

        assertEq(vault.feeManager(), newFeeManager);
    }

    function test_RevertWhen_NonAdminUpdatesMultisig() public {
        vm.prank(user);
        vm.expectRevert(TreasuryUSDCVault.OnlyAdmin.selector);
        vault.setTreasuryMultisig(makeAddr("newMultisig"));
    }

    function test_RevertWhen_SetMultisigToZero() public {
        vm.prank(admin);
        vm.expectRevert(TreasuryUSDCVault.ZeroAddress.selector);
        vault.setTreasuryMultisig(address(0));
    }

    // =========== View Functions Tests ===========

    function test_GetBalance() public {
        uint256 depositAmount = 10_000e6;

        vm.startPrank(feeManager);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(APP_ID_1, depositAmount, 1);
        vm.stopPrank();

        assertEq(vault.balance(), depositAmount);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_Deposit(uint256 amount) public {
        // USDC has 6 decimals, bound to reasonable amounts
        amount = bound(amount, 1, 10_000_000e6);

        vm.startPrank(feeManager);
        usdc.approve(address(vault), amount);
        vault.deposit(APP_ID_1, amount, 1);
        vm.stopPrank();

        assertEq(vault.totalRevenue(), amount);
        assertEq(vault.revenueByApp(APP_ID_1), amount);
    }

    function testFuzz_DepositAndWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, 10_000_000e6);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.startPrank(feeManager);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(APP_ID_1, depositAmount, 1);
        vm.stopPrank();

        vm.prank(treasuryMultisig);
        vault.withdraw(withdrawAmount);

        assertEq(usdc.balanceOf(treasuryMultisig), withdrawAmount);
        assertEq(vault.balance(), depositAmount - withdrawAmount);
    }
}
