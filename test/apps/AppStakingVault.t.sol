// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract AppStakingVaultTest is Test {
    AppStakingVault public vault;
    AppToken public appToken;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public admin = makeAddr("admin");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 ether;

    event Staked(address indexed user, uint256 amount, uint256 newBalance);
    event Unstaked(address indexed user, uint256 amount, uint256 newBalance);

    function setUp() public {
        appToken = new AppToken(
            "TestApp",
            "TEST",
            18,
            MAX_SUPPLY,
            owner,
            admin,
            address(1),
            address(1),
            address(1),
            address(1)
        );
        vault = new AppStakingVault("TestApp", "TAPP", appToken, owner);

        // Mint tokens to users
        vm.startPrank(admin);
        appToken.mint(user1, 10000 ether);
        appToken.mint(user2, 10000 ether);

        // Make vault exempt from transfer fees to avoid circular fee issues
        appToken.setTransferFeeExempt(address(vault), true);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // DEPLOYMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Deployment() public {
        assertEq(address(vault.APP()), address(appToken));
        assertEq(vault.owner(), owner);
        assertEq(vault.totalStaked(), 0);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // STAKE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Stake() public {
        uint256 amount = 1000 ether;

        vm.startPrank(user1);
        appToken.approve(address(vault), amount);

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, amount, amount);

        vault.stake(amount);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), amount);
        assertEq(vault.totalStaked(), amount);
        assertEq(appToken.balanceOf(address(vault)), amount);
    }

    function test_StakeMultipleTimes() public {
        vm.startPrank(user1);

        // First stake
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        assertEq(vault.stakedOf(user1), 1000 ether);

        // Second stake
        appToken.approve(address(vault), 500 ether);
        vault.stake(500 ether);
        assertEq(vault.stakedOf(user1), 1500 ether);

        vm.stopPrank();

        assertEq(vault.totalStaked(), 1500 ether);
    }

    function test_StakeFromMultipleUsers() public {
        // User1 stakes
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        vm.stopPrank();

        // User2 stakes
        vm.startPrank(user2);
        appToken.approve(address(vault), 2000 ether);
        vault.stake(2000 ether);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), 1000 ether);
        assertEq(vault.stakedOf(user2), 2000 ether);
        assertEq(vault.totalStaked(), 3000 ether);
    }

    function test_RevertWhen_StakeZero() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(user1);
        vault.stake(0);
    }

    function test_RevertWhen_StakeWithoutApproval() public {
        vm.expectRevert();
        vm.prank(user1);
        vault.stake(1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // UNSTAKE TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Unstake() public {
        // Stake first
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);

        // Unstake
        vm.expectEmit(true, true, true, true);
        emit Unstaked(user1, 500 ether, 500 ether);

        vault.unstake(500 ether);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), 500 ether);
        assertEq(vault.totalStaked(), 500 ether);
        assertEq(appToken.balanceOf(user1), 9500 ether);
    }

    function test_UnstakeAll() public {
        uint256 amount = 1000 ether;

        // Stake
        vm.startPrank(user1);
        appToken.approve(address(vault), amount);
        vault.stake(amount);

        // Unstake all
        vault.unstake(amount);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), 0);
        assertEq(vault.totalStaked(), 0);
        assertEq(appToken.balanceOf(user1), 10000 ether);
    }

    function test_RevertWhen_UnstakeZero() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(user1);
        vault.unstake(0);
    }

    function test_RevertWhen_UnstakeMoreThanStaked() public {
        // Stake 1000
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);

        // Try to unstake 1001
        vm.expectRevert(AppStakingVault.Insufficient.selector);
        vault.unstake(1001 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_UnstakeWithNoStake() public {
        vm.expectRevert(AppStakingVault.Insufficient.selector);
        vm.prank(user1);
        vault.unstake(1000 ether);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // INTEGRATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_StakeUnstakeSequence() public {
        vm.startPrank(user1);

        // Stake 1000
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);
        assertEq(vault.stakedOf(user1), 1000 ether);

        // Unstake 300
        vault.unstake(300 ether);
        assertEq(vault.stakedOf(user1), 700 ether);

        // Stake 500 more
        appToken.approve(address(vault), 500 ether);
        vault.stake(500 ether);
        assertEq(vault.stakedOf(user1), 1200 ether);

        // Unstake all
        vault.unstake(1200 ether);
        assertEq(vault.stakedOf(user1), 0);

        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, 1, 10000 ether);

        vm.startPrank(user1);
        appToken.approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), amount);
        assertEq(vault.totalStaked(), amount);
    }

    function testFuzz_StakeAndUnstake(uint256 stakeAmount, uint256 unstakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, 10000 ether);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        vm.startPrank(user1);
        appToken.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);

        vault.unstake(unstakeAmount);
        vm.stopPrank();

        assertEq(vault.stakedOf(user1), stakeAmount - unstakeAmount);
        assertEq(vault.totalStaked(), stakeAmount - unstakeAmount);
    }
}
