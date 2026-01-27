// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakingFuzz
 * @notice Comprehensive fuzz tests for staking systems
 */
contract StakingFuzz is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppToken public appToken;
    AppStakingVault public vault;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, admin, admin, governance, treasury, treasury, treasury
        );

        // Deploy AppStakingVault
        vault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), admin);

        // Mint app tokens for testing
        vm.startPrank(admin);
        appToken.mint(user1, 5_000_000 ether);
        appToken.mint(user2, 5_000_000 ether);
        elta.transfer(user1, 10_000_000 ether);
        elta.transfer(user2, 10_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VeELTA FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_VeELTA_BoostCalculation(uint256 durationDays) public {
        durationDays = bound(durationDays, 8, 730); // MIN_LOCK+1 to MAX_LOCK
        uint256 amount = 1000 ether;

        vm.startPrank(user1);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + durationDays * 1 days));
        vm.stopPrank();

        uint256 veBalance = veElta.balanceOf(user1);

        // Boost should be between 1x and 2x
        assertGe(veBalance, amount, "Boost should be >= 1x");
        assertLe(veBalance, amount * 2, "Boost should be <= 2x");

        // Longer duration = higher boost
        console2.log("Duration (days):", durationDays);
        console2.log("VeELTA balance:", veBalance);
        console2.log("Boost ratio (1e18):", (veBalance * 1e18) / amount);
    }

    function testFuzz_VeELTA_ExtendLock(uint256 initialDays, uint256 extendDays) public {
        initialDays = bound(initialDays, 8, 365);
        extendDays = bound(extendDays, initialDays + 1, 730);

        uint256 amount = 1000 ether;

        vm.startPrank(user1);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + initialDays * 1 days));

        uint256 veBefore = veElta.balanceOf(user1);

        // Extend to longer duration
        veElta.extendLock(uint64(block.timestamp + extendDays * 1 days));

        uint256 veAfter = veElta.balanceOf(user1);
        vm.stopPrank();

        // Extended lock should have equal or higher voting power
        assertGe(veAfter, veBefore, "Extended lock should not decrease voting power");
    }

    function testFuzz_VeELTA_MultipleUsers(uint8 numUsers) public {
        numUsers = uint8(bound(numUsers, 2, 10));

        uint256 totalVe = 0;

        for (uint256 i = 0; i < numUsers; i++) {
            address testUser = address(uint160(0x1000 + i));
            uint256 amount = 100_000 ether; // Fixed amount per user

            // Fund user
            vm.prank(admin);
            elta.transfer(testUser, amount);

            // Lock
            vm.startPrank(testUser);
            elta.approve(address(veElta), amount);
            veElta.lock(amount, uint64(block.timestamp + 180 days));
            vm.stopPrank();

            totalVe += veElta.balanceOf(testUser);
        }

        // Total veELTA should match total supply
        assertEq(veElta.totalSupply(), totalVe, "Total supply should match sum of balances");
    }

    function testFuzz_VeELTA_Delegation(address delegatee) public {
        vm.assume(delegatee != address(0) && delegatee != user1);

        uint256 amount = 1000 ether;

        vm.startPrank(user1);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + 365 days));

        uint256 user1Votes = veElta.getVotes(user1);

        // Delegate
        veElta.delegate(delegatee);

        assertEq(veElta.getVotes(delegatee), user1Votes, "Delegatee should have user's votes");
        assertEq(veElta.getVotes(user1), 0, "User should have 0 votes after delegation");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // APP STAKING VAULT FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_AppVault_Stake(uint256 amount) public {
        amount = bound(amount, 1 ether, 2_000_000 ether);

        vm.startPrank(user1);
        appToken.approve(address(vault), amount);

        uint256 balanceBefore = appToken.balanceOf(user1);
        vault.stake(amount);
        uint256 balanceAfter = appToken.balanceOf(user1);

        assertEq(balanceBefore - balanceAfter, amount, "Should deduct exact stake amount");
        assertEq(vault.balanceOf(user1), amount, "Should credit stake to user");
        vm.stopPrank();
    }

    function testFuzz_AppVault_Unstake(uint256 stakeAmount, uint256 unstakeAmount) public {
        stakeAmount = bound(stakeAmount, 1 ether, 2_000_000 ether);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        vm.startPrank(user1);
        appToken.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);

        uint256 stakedBefore = vault.balanceOf(user1);
        vault.unstake(unstakeAmount);
        uint256 stakedAfter = vault.balanceOf(user1);

        assertEq(stakedBefore - stakedAfter, unstakeAmount, "Should reduce stake by unstake amount");
        vm.stopPrank();
    }

    function testFuzz_AppVault_MultipleStakes(uint256[] calldata amounts) public {
        vm.assume(amounts.length > 0 && amounts.length <= 5);

        uint256 totalStaked = 0;

        vm.startPrank(user1);
        appToken.approve(address(vault), 5_000_000 ether);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amt = bound(amounts[i], 1 ether, 500_000 ether);
            if (totalStaked + amt > 4_000_000 ether) break;

            vault.stake(amt);
            totalStaked += amt;
        }
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), totalStaked, "Total staked should match");
    }

    function testFuzz_AppVault_PartialUnstake(uint256 stakeAmount, uint8 numUnstakes) public {
        stakeAmount = bound(stakeAmount, 10 ether, 1_000_000 ether);
        numUnstakes = uint8(bound(numUnstakes, 1, 5));

        vm.startPrank(user1);
        appToken.approve(address(vault), stakeAmount);
        vault.stake(stakeAmount);

        uint256 remaining = stakeAmount;
        uint256 unstakeEach = stakeAmount / numUnstakes;

        for (uint256 i = 0; i < numUnstakes - 1; i++) {
            vault.unstake(unstakeEach);
            remaining -= unstakeEach;
        }

        // Unstake remainder
        vault.unstake(remaining);

        assertEq(vault.balanceOf(user1), 0, "Should be fully unstaked");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMBINED STAKING SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Combined_VeELTAAndAppStaking(uint256 eltaAmount, uint256 appAmount) public {
        eltaAmount = bound(eltaAmount, 1 ether, 5_000_000 ether);
        appAmount = bound(appAmount, 1 ether, 2_000_000 ether);

        // Lock ELTA for veELTA
        vm.startPrank(user1);
        elta.approve(address(veElta), eltaAmount);
        veElta.lock(eltaAmount, uint64(block.timestamp + 365 days));

        // Stake app tokens
        appToken.approve(address(vault), appAmount);
        vault.stake(appAmount);
        vm.stopPrank();

        // Verify both positions
        (uint128 lockedPrincipal,) = veElta.locks(user1);
        assertEq(lockedPrincipal, eltaAmount, "ELTA locked amount incorrect");
        assertEq(vault.balanceOf(user1), appAmount, "App staked amount incorrect");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Edge_StakeZero() public {
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);

        vm.expectRevert();
        vault.stake(0);
        vm.stopPrank();
    }

    function test_Edge_UnstakeMoreThanStaked() public {
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);
        vault.stake(1000 ether);

        vm.expectRevert();
        vault.unstake(1001 ether);
        vm.stopPrank();
    }

    function test_Edge_VeELTA_LockAtMinDuration() public {
        uint256 amount = 1000 ether;
        uint64 minLock = veElta.MIN_LOCK();

        vm.startPrank(user1);
        elta.approve(address(veElta), amount);

        // Exactly at MIN_LOCK should fail
        vm.expectRevert();
        veElta.lock(amount, uint64(block.timestamp + minLock));
        vm.stopPrank();
    }

    function test_Edge_VeELTA_LockAtMaxDuration() public {
        uint256 amount = 1000 ether;
        uint64 maxLock = veElta.MAX_LOCK();

        vm.startPrank(user1);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + maxLock));

        uint256 veBalance = veElta.balanceOf(user1);
        // At max lock, should get close to 2x boost
        assertGe(veBalance, (amount * 19) / 10, "Should get near-max boost");
        vm.stopPrank();
    }
}
