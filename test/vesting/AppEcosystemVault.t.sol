// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppEcosystemVault} from "../../src/vesting/AppEcosystemVault.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AppEcosystemVaultTest is Test {
    MockToken public token;
    MockToken public otherToken;
    AppEcosystemVault public vault;

    address public admin = makeAddr("admin");
    address public recipient = makeAddr("recipient");
    address public unauthorized = makeAddr("unauthorized");

    uint256 public constant APP_ID = 1;
    uint256 public constant INITIAL_BALANCE = 250_000 ether;

    function setUp() public {
        token = new MockToken();
        otherToken = new MockToken();

        vault = new AppEcosystemVault(APP_ID, address(token), admin);

        // Fund vault
        token.transfer(address(vault), INITIAL_BALANCE);
    }

    // =========== Deployment Tests ===========

    function test_Deploy() public view {
        assertEq(vault.appId(), APP_ID);
        assertEq(vault.token(), address(token));
        assertEq(vault.admin(), admin);
        assertEq(vault.balance(), INITIAL_BALANCE);
    }

    function test_RevertWhen_DeployWithZeroToken() public {
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        new AppEcosystemVault(APP_ID, address(0), admin);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        new AppEcosystemVault(APP_ID, address(token), address(0));
    }

    // =========== Withdraw Tests ===========

    function test_Withdraw() public {
        uint256 amount = 50_000 ether;

        vm.prank(admin);
        vault.withdraw(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(vault.balance(), INITIAL_BALANCE - amount);
    }

    function test_WithdrawEmitsEvent() public {
        uint256 amount = 50_000 ether;

        vm.expectEmit(true, true, false, true);
        emit AppEcosystemVault.TokensWithdrawn(address(token), recipient, amount);

        vm.prank(admin);
        vault.withdraw(recipient, amount);
    }

    function test_RevertWhen_UnauthorizedWithdraw() public {
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vm.prank(unauthorized);
        vault.withdraw(recipient, 1000 ether);
    }

    function test_RevertWhen_WithdrawToZeroAddress() public {
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        vm.prank(admin);
        vault.withdraw(address(0), 1000 ether);
    }

    function test_RevertWhen_WithdrawZeroAmount() public {
        vm.expectRevert(AppEcosystemVault.ZeroAmount.selector);
        vm.prank(admin);
        vault.withdraw(recipient, 0);
    }

    function test_RevertWhen_WithdrawInsufficientBalance() public {
        vm.expectRevert(AppEcosystemVault.InsufficientBalance.selector);
        vm.prank(admin);
        vault.withdraw(recipient, INITIAL_BALANCE + 1);
    }

    // =========== WithdrawAny Tests ===========

    function test_WithdrawAny() public {
        otherToken.transfer(address(vault), 10_000 ether);

        vm.prank(admin);
        vault.withdrawAny(address(otherToken), recipient, 5_000 ether);

        assertEq(otherToken.balanceOf(recipient), 5_000 ether);
        assertEq(otherToken.balanceOf(address(vault)), 5_000 ether);
    }

    function test_RevertWhen_UnauthorizedWithdrawAny() public {
        otherToken.transfer(address(vault), 10_000 ether);

        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vm.prank(unauthorized);
        vault.withdrawAny(address(otherToken), recipient, 1000 ether);
    }

    // =========== Admin Tests ===========

    function test_SetAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        vault.setAdmin(newAdmin);

        assertEq(vault.admin(), newAdmin);
    }

    function test_SetAdminEmitsEvent() public {
        address newAdmin = makeAddr("newAdmin");

        vm.expectEmit(true, true, false, false);
        emit AppEcosystemVault.AdminUpdated(admin, newAdmin);

        vm.prank(admin);
        vault.setAdmin(newAdmin);
    }

    function test_RevertWhen_UnauthorizedSetAdmin() public {
        vm.expectRevert(AppEcosystemVault.Unauthorized.selector);
        vm.prank(unauthorized);
        vault.setAdmin(makeAddr("newAdmin"));
    }

    function test_RevertWhen_SetAdminToZero() public {
        vm.expectRevert(AppEcosystemVault.ZeroAddress.selector);
        vm.prank(admin);
        vault.setAdmin(address(0));
    }

    // =========== View Tests ===========

    function test_Balance() public view {
        assertEq(vault.balance(), INITIAL_BALANCE);
    }

    function test_BalanceOf() public {
        otherToken.transfer(address(vault), 5_000 ether);
        assertEq(vault.balanceOf(address(otherToken)), 5_000 ether);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_Withdraw(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(admin);
        vault.withdraw(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(vault.balance(), INITIAL_BALANCE - amount);
    }

    function testFuzz_MultipleWithdrawals(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, INITIAL_BALANCE / 2);
        amount2 = bound(amount2, 1, INITIAL_BALANCE - amount1);

        vm.startPrank(admin);
        vault.withdraw(recipient, amount1);
        vault.withdraw(recipient, amount2);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), amount1 + amount2);
        assertEq(vault.balance(), INITIAL_BALANCE - amount1 - amount2);
    }
}
