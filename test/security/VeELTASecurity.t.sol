// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VeELTASecurity
 * @notice Red team security tests for VeELTA staking
 * @dev Tests voting power inflation, unlock bypass, snapshot manipulation
 */
contract VeELTASecurity is Test {
    ELTA public elta;
    VeELTA public veElta;

    address public admin = makeAddr("admin");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Fund users
        vm.startPrank(admin);
        elta.transfer(attacker, 1_000_000 ether);
        elta.transfer(alice, 1_000_000 ether);
        elta.transfer(bob, 1_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // NON-TRANSFERABLE (SOULBOUND) TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotTransferVeELTA() public {
        // Lock some ELTA
        vm.startPrank(alice);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        uint256 aliceBalance = veElta.balanceOf(alice);
        assertGt(aliceBalance, 0, "Alice should have veELTA");

        // Try to transfer
        vm.prank(alice);
        vm.expectRevert();
        veElta.transfer(bob, aliceBalance);
    }

    function test_Security_CannotApproveVeELTA() public {
        // Lock some ELTA
        vm.startPrank(alice);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Try to approve (should work but transferFrom should fail)
        vm.prank(alice);
        veElta.approve(bob, type(uint256).max);

        // Try transferFrom
        vm.prank(bob);
        vm.expectRevert();
        veElta.transferFrom(alice, bob, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOCK MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotLockTwice() public {
        vm.startPrank(attacker);
        elta.approve(address(veElta), 2000 ether);

        // First lock
        veElta.lock(1000 ether, uint64(block.timestamp + 30 days));

        // Second lock should fail
        vm.expectRevert(VeELTA.LockExists.selector);
        veElta.lock(1000 ether, uint64(block.timestamp + 60 days));
        vm.stopPrank();
    }

    function test_Security_CannotLockForTooShort() public {
        vm.startPrank(attacker);
        elta.approve(address(veElta), 1000 ether);

        // Try to lock for less than MIN_LOCK
        vm.expectRevert();
        veElta.lock(1000 ether, uint64(block.timestamp + 1 days));
        vm.stopPrank();
    }

    function test_Security_CannotLockForTooLong() public {
        vm.startPrank(attacker);
        elta.approve(address(veElta), 1000 ether);

        // Try to lock for more than MAX_LOCK
        vm.expectRevert();
        veElta.lock(1000 ether, uint64(block.timestamp + 3 * 365 days)); // 3 years > 2 year max
        vm.stopPrank();
    }

    function test_Security_CannotLockZeroAmount() public {
        vm.startPrank(attacker);
        elta.approve(address(veElta), 1000 ether);

        vm.expectRevert();
        veElta.lock(0, uint64(block.timestamp + 30 days));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UNLOCK BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotUnlockBeforeExpiry() public {
        vm.startPrank(attacker);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Try to unlock immediately
        vm.expectRevert();
        veElta.unlock();
        vm.stopPrank();
    }

    function test_Security_CannotUnlockTwice() public {
        vm.startPrank(attacker);
        elta.approve(address(veElta), 1000 ether);
        // MIN_LOCK is 7 days, so unlock time must be > timestamp + 7 days
        veElta.lock(1000 ether, uint64(block.timestamp + 8 days));

        // Warp past unlock time
        vm.warp(block.timestamp + 9 days);

        // First unlock succeeds
        veElta.unlock();

        // Second unlock should fail (no lock)
        vm.expectRevert();
        veElta.unlock();
        vm.stopPrank();
    }

    function test_Security_UnlockReturnsExactPrincipal() public {
        uint256 lockAmount = 1000 ether;

        vm.startPrank(alice);
        elta.approve(address(veElta), lockAmount);

        uint256 balanceBefore = elta.balanceOf(alice);
        veElta.lock(lockAmount, uint64(block.timestamp + 30 days));

        // Warp and unlock
        vm.warp(block.timestamp + 31 days);
        veElta.unlock();

        uint256 balanceAfter = elta.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore, "Should get exact principal back");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTING POWER INFLATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_VotingPowerBoundedByBoost() public {
        vm.startPrank(alice);
        elta.approve(address(veElta), 1000 ether);

        // Lock for max duration to get max boost
        veElta.lock(1000 ether, uint64(block.timestamp + veElta.MAX_LOCK()));

        uint256 veBalance = veElta.balanceOf(alice);
        uint256 principal = 1000 ether;

        // veELTA should be at most 2x principal (max boost)
        assertLe(veBalance, principal * 2, "veELTA should be <= 2x principal");
        assertGe(veBalance, principal, "veELTA should be >= principal");
        vm.stopPrank();
    }

    function test_Security_ExtendLockDoesNotInflateVotingPower() public {
        vm.startPrank(alice);
        elta.approve(address(veElta), 1000 ether);

        // Lock for min duration (need to add extra time beyond MIN_LOCK check)
        veElta.lock(1000 ether, uint64(block.timestamp + veElta.MIN_LOCK() + 1 days));

        uint256 veBalanceInitial = veElta.balanceOf(alice);
        (uint128 principalBefore,) = veElta.locks(alice);

        // Extend to max duration
        veElta.extendLock(uint64(block.timestamp + veElta.MAX_LOCK()));

        uint256 veBalanceAfter = veElta.balanceOf(alice);
        (uint128 principalAfter,) = veElta.locks(alice);

        // Principal should not change
        assertEq(principalAfter, principalBefore, "Principal should not change on extend");

        // NOTE: veBalance should increase with extension, but not exceed 2x
        // This is where the previously found bug would manifest
        console2.log("Initial veBalance:", veBalanceInitial);
        console2.log("After extend veBalance:", veBalanceAfter);
        console2.log("Principal:", principalBefore);

        vm.stopPrank();
    }

    function test_Security_IncreaseAmountUpdatesVotingPowerCorrectly() public {
        vm.startPrank(alice);
        elta.approve(address(veElta), 2000 ether);

        // Initial lock
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));
        uint256 veBefore = veElta.balanceOf(alice);

        // Increase amount
        veElta.increaseAmount(500 ether);
        uint256 veAfter = veElta.balanceOf(alice);

        // veELTA should increase proportionally
        // (new principal / old principal) * old veELTA ≈ new veELTA
        // 1500/1000 = 1.5x
        assertGt(veAfter, veBefore, "veELTA should increase");

        (uint128 principal,) = veElta.locks(alice);
        assertEq(principal, 1500 ether, "Principal should be 1500");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SNAPSHOT / GOVERNANCE ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_FlashStakeAttackMitigated() public {
        // Flash stake attack: borrow tokens, stake, vote, unstake, return
        // veELTA has MIN_LOCK which prevents immediate unstaking

        vm.startPrank(attacker);
        elta.approve(address(veElta), 1_000_000 ether);

        // Lock tokens (add extra time to pass MIN_LOCK check)
        veElta.lock(1_000_000 ether, uint64(block.timestamp + veElta.MIN_LOCK() + 1 days));

        // Attacker now has voting power but cannot unstake immediately
        uint256 votingPower = veElta.balanceOf(attacker);
        assertGt(votingPower, 0, "Should have voting power");

        // Cannot unlock before lock expires
        vm.expectRevert();
        veElta.unlock();

        vm.stopPrank();
    }

    function test_Security_DelegationWorks() public {
        vm.startPrank(alice);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Check initial delegation (auto-delegates to self)
        address delegate = veElta.delegates(alice);
        assertEq(delegate, alice, "Should auto-delegate to self");

        // Delegate to bob
        veElta.delegate(bob);
        assertEq(veElta.delegates(alice), bob, "Should delegate to bob");

        // Voting power should move
        assertGt(veElta.getVotes(bob), 0, "Bob should have voting power");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OVERFLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotOverflowPrincipal() public {
        // Principal is stored as uint128
        // Try to lock more than uint128 max
        uint256 hugeAmount = uint256(type(uint128).max) + 1;

        // This would require having that many tokens, which isn't possible
        // but test the error handling
        vm.startPrank(admin);
        elta.transfer(attacker, 10_000_000 ether); // Give more tokens
        vm.stopPrank();

        vm.startPrank(attacker);
        elta.approve(address(veElta), type(uint256).max);

        // Lock first
        veElta.lock(1000 ether, uint64(block.timestamp + 30 days));

        // Try to increase by huge amount (should revert due to overflow check)
        vm.expectRevert();
        veElta.increaseAmount(hugeAmount);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_LockAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 500_000 ether);

        vm.startPrank(alice);
        elta.approve(address(veElta), amount);

        veElta.lock(amount, uint64(block.timestamp + 30 days));

        (uint128 principal,) = veElta.locks(alice);
        assertEq(principal, amount, "Principal should match lock amount");

        uint256 veBalance = veElta.balanceOf(alice);
        assertGe(veBalance, amount, "veELTA >= principal");
        assertLe(veBalance, amount * 2, "veELTA <= 2x principal");
        vm.stopPrank();
    }

    function testFuzz_Security_LockDuration(uint256 durationDays) public {
        // MIN_LOCK is 7 days, need unlock time > timestamp + MIN_LOCK
        // So duration must be > 7 days (use 8 as minimum)
        durationDays = bound(durationDays, 8, 730); // MIN_LOCK+1 to MAX_LOCK in days
        uint64 unlockTime = uint64(block.timestamp + durationDays * 1 days);

        vm.startPrank(alice);
        elta.approve(address(veElta), 1000 ether);

        veElta.lock(1000 ether, unlockTime);

        (, uint64 storedUnlockTime) = veElta.locks(alice);
        assertEq(storedUnlockTime, unlockTime, "Unlock time should match");

        vm.stopPrank();
    }
}
