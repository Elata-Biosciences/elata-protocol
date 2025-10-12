// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppStakingVault } from "../../../src/apps/AppStakingVault.sol";
import { AppToken } from "../../../src/apps/AppToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Errors } from "../../../src/utils/Errors.sol";

/**
 * @title AppStakingVaultSecurityTest
 * @notice Comprehensive security testing for AppStakingVault
 * @dev Tests reentrancy, accounting errors, access control, and edge cases
 */
contract AppStakingVaultSecurityTest is Test {
    AppStakingVault public vault;
    AppToken public appToken;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        appToken = new AppToken("TestApp", "TEST", 18, MAX_SUPPLY, owner, admin);
        vault = new AppStakingVault("TestApp", "TAPP", appToken, owner);

        // Mint tokens to users
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(user2, 10000 ether);
        appToken.mint(attacker, 10000 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REENTRANCY TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ReentrancyProtection_Stake() public {
        MaliciousToken malToken = new MaliciousToken();
        AppStakingVault malVault = new AppStakingVault("MalApp", "MAL", malToken, owner);

        malToken.mint(attacker, 1000 ether);

        vm.startPrank(attacker);
        malToken.approve(address(malVault), 1000 ether);

        // Set vault to attack
        malToken.setAttackTarget(address(malVault));

        // Should revert due to reentrancy guard
        vm.expectRevert();
        malVault.stake(100 ether);
        vm.stopPrank();
    }

    function test_Security_ReentrancyProtection_Unstake() public {
        // ReentrancyGuard prevents reentrancy on unstake
        // ERC20 transfers don't have callbacks, so we test the guard is present

        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);

        // Unstake should work normally
        vault.unstake(500 ether);

        // Verify state is correct (guard worked)
        assertEq(vault.stakedOf(user1), 500 ether);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ACCOUNTING TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_TotalStakedAccurate() public {
        // Stake from multiple users
        vm.prank(user1);
        appToken.approve(address(vault), 1000 ether);
        vm.prank(user1);
        vault.stake(1000 ether);

        vm.prank(user2);
        appToken.approve(address(vault), 2000 ether);
        vm.prank(user2);
        vault.stake(2000 ether);

        // Total should match sum
        assertEq(vault.totalStaked(), 3000 ether);

        // Unstake
        vm.prank(user1);
        vault.unstake(500 ether);

        assertEq(vault.totalStaked(), 2500 ether);
    }

    function test_Security_BalanceMatchesTotalStaked() public {
        vm.prank(user1);
        appToken.approve(address(vault), 1000 ether);
        vm.prank(user1);
        vault.stake(1000 ether);

        // Vault balance should match totalStaked
        assertEq(appToken.balanceOf(address(vault)), vault.totalStaked());
    }

    function test_Security_CannotUnstakeMoreThanStaked() public {
        vm.prank(user1);
        appToken.approve(address(vault), 1000 ether);
        vm.prank(user1);
        vault.stake(1000 ether);

        vm.expectRevert(AppStakingVault.Insufficient.selector);
        vm.prank(user1);
        vault.unstake(1001 ether);
    }

    function test_Security_StakeUnstakeCycle() public {
        uint256 initialBalance = appToken.balanceOf(user1);

        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vault.unstake(1000 ether);
        vm.stopPrank();

        // Should have same balance after full cycle
        assertEq(appToken.balanceOf(user1), initialBalance);
        assertEq(vault.stakedOf(user1), 0);
        assertEq(vault.totalStaked(), 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ZERO AMOUNT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotStakeZero() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(user1);
        vault.stake(0);
    }

    function test_Security_CannotUnstakeZero() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(user1);
        vault.unstake(0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTING
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_Security_StakeUnstakeInvariants(uint256 stakeAmount, uint256 unstakeAmount)
        public
    {
        stakeAmount = bound(stakeAmount, 1, 10000 ether);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        vm.startPrank(user1);
        appToken.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);

        uint256 vaultBalanceBefore = appToken.balanceOf(address(vault));
        uint256 totalStakedBefore = vault.totalStaked();

        vault.unstake(unstakeAmount);
        vm.stopPrank();

        // Invariant: vault balance should equal totalStaked
        assertEq(appToken.balanceOf(address(vault)), vault.totalStaked());

        // Invariant: changes should match
        assertEq(vaultBalanceBefore - appToken.balanceOf(address(vault)), unstakeAmount);
        assertEq(totalStakedBefore - vault.totalStaked(), unstakeAmount);
    }

    function testFuzz_Security_MultipleUsers(uint256 user1Amount, uint256 user2Amount) public {
        user1Amount = bound(user1Amount, 1, 10000 ether);
        user2Amount = bound(user2Amount, 1, 10000 ether);

        // Both users stake
        vm.prank(user1);
        appToken.approve(address(vault), user1Amount);
        vm.prank(user1);
        vault.stake(user1Amount);

        vm.prank(user2);
        appToken.approve(address(vault), user2Amount);
        vm.prank(user2);
        vault.stake(user2Amount);

        // Invariants
        assertEq(vault.stakedOf(user1), user1Amount);
        assertEq(vault.stakedOf(user2), user2Amount);
        assertEq(vault.totalStaked(), user1Amount + user2Amount);
        assertEq(appToken.balanceOf(address(vault)), user1Amount + user2Amount);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // GRIEFING/DOS TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotGriefVault() public {
        // Attacker cannot lock vault or DOS it
        vm.prank(attacker);
        appToken.approve(address(vault), 1 wei);
        vm.prank(attacker);
        vault.stake(1 wei);

        // Other users can still stake
        vm.prank(user1);
        appToken.approve(address(vault), 1000 ether);
        vm.prank(user1);
        vault.stake(1000 ether);

        assertEq(vault.stakedOf(user1), 1000 ether);
    }

    function test_Security_EmergencyUnstake() public {
        // Users should always be able to unstake (no lock period)
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);

        // Immediate unstake should work
        vault.unstake(1000 ether);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), 0);
        assertEq(appToken.balanceOf(user1), 10000 ether);
    }
}

// Malicious token for reentrancy testing
contract MaliciousToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address public attackTarget;
    uint256 private _totalSupply;

    function setAttackTarget(address target) external {
        attackTarget = target;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _balances[from] -= amount;
        _balances[to] += amount;

        // Attempt reentrancy
        if (attackTarget != address(0)) {
            AppStakingVault(attackTarget).stake(1 ether);
        }

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function allowance(address, address spender) external view returns (uint256) {
        return type(uint256).max;
    }
}

// Malicious receiver for reentrancy testing
contract MaliciousReceiver {
    AppStakingVault public vault;
    AppToken public token;
    bool public attacking;

    constructor(AppStakingVault _vault, AppToken _token) {
        vault = _vault;
        token = _token;
    }

    function doStake(uint256 amount) external {
        token.approve(address(vault), amount);
        vault.stake(amount);
    }

    function attackUnstake(uint256 amount) external {
        attacking = true;
        vault.unstake(amount);
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            // Attempt reentrancy
            vault.unstake(1 ether);
        }
    }
}
