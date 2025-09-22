// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract VeELTATest is Test {
    VeELTA public veELTA;
    ELTA public elta;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant INITIAL_MINT = 10_000_000 ether;
    uint256 public constant MAX_SUPPLY = 77_000_000 ether;

    event LockCreated(address indexed user, uint256 amount, uint256 start, uint256 end);
    event LockIncreased(address indexed user, uint256 addedAmount, uint256 newAmount);
    event UnlockExtended(address indexed user, uint256 oldEnd, uint256 newEnd);
    event Withdrawn(address indexed user, uint256 amount);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, INITIAL_MINT, MAX_SUPPLY);
        veELTA = new VeELTA(elta, admin);

        // Give users some ELTA
        vm.startPrank(treasury);
        elta.transfer(user1, 10000 ether);
        elta.transfer(user2, 10000 ether);
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(veELTA.ELTA()), address(elta));
        assertEq(veELTA.MIN_LOCK(), 1 weeks);
        assertEq(veELTA.MAX_LOCK(), 104 weeks);
        assertTrue(veELTA.hasRole(veELTA.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(veELTA.hasRole(veELTA.MANAGER_ROLE(), admin));
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new VeELTA(ELTA(address(0)), admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new VeELTA(elta, address(0));
    }

    function test_CreateLock() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks; // 1 year

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);

        vm.expectEmit(true, false, false, true);
        emit LockCreated(user1, amount, block.timestamp, block.timestamp + lockDuration);

        veELTA.createLock(amount, lockDuration);
        vm.stopPrank();

        (uint128 lockAmount, uint64 start, uint64 end) = veELTA.locks(user1);
        assertEq(lockAmount, amount);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + lockDuration);
        assertEq(elta.balanceOf(address(veELTA)), amount);
        assertEq(elta.balanceOf(user1), 10000 ether - amount);
    }

    function test_RevertWhen_CreateLockZeroAmount() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(user1);
        veELTA.createLock(0, 52 weeks);
    }

    function test_RevertWhen_CreateLockTooShort() public {
        vm.expectRevert(Errors.LockTooShort.selector);
        vm.prank(user1);
        veELTA.createLock(1000 ether, 6 days);
    }

    function test_RevertWhen_CreateLockTooLong() public {
        vm.expectRevert(Errors.LockTooLong.selector);
        vm.prank(user1);
        veELTA.createLock(1000 ether, 105 weeks);
    }

    function test_RevertWhen_CreateLockAlreadyActive() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount * 2);
        veELTA.createLock(amount, lockDuration);

        vm.expectRevert(Errors.LockActive.selector);
        veELTA.createLock(amount, lockDuration);
        vm.stopPrank();
    }

    function test_IncreaseAmount() public {
        uint256 initialAmount = 1000 ether;
        uint256 addedAmount = 500 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), initialAmount + addedAmount);
        veELTA.createLock(initialAmount, lockDuration);

        vm.expectEmit(true, false, false, true);
        emit LockIncreased(user1, addedAmount, initialAmount + addedAmount);

        veELTA.increaseAmount(addedAmount);
        vm.stopPrank();

        (uint128 lockAmount,,) = veELTA.locks(user1);
        assertEq(lockAmount, initialAmount + addedAmount);
        assertEq(elta.balanceOf(address(veELTA)), initialAmount + addedAmount);
    }

    function test_RevertWhen_IncreaseAmountZero() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);

        vm.expectRevert(Errors.InvalidAmount.selector);
        veELTA.increaseAmount(0);
        vm.stopPrank();
    }

    function test_RevertWhen_IncreaseAmountNoActiveLock() public {
        vm.expectRevert(Errors.NoActiveLock.selector);
        vm.prank(user1);
        veELTA.increaseAmount(500 ether);
    }

    function test_IncreaseUnlockTime() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;
        uint256 extension = 26 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);

        uint256 oldEnd = block.timestamp + lockDuration;
        uint256 newEnd = oldEnd + extension;

        vm.expectEmit(true, false, false, true);
        emit UnlockExtended(user1, oldEnd, newEnd);

        veELTA.increaseUnlockTime(newEnd);
        vm.stopPrank();

        (,, uint64 end) = veELTA.locks(user1);
        assertEq(end, newEnd);
    }

    function test_RevertWhen_IncreaseUnlockTimeTooShort() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);

        vm.expectRevert(Errors.LockTooShort.selector);
        veELTA.increaseUnlockTime(block.timestamp + lockDuration - 1 weeks);
        vm.stopPrank();
    }

    function test_RevertWhen_IncreaseUnlockTimeTooLong() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);

        // Try to extend beyond MAX_LOCK from start
        uint256 tooLongEnd = block.timestamp + veELTA.MAX_LOCK() + 1;

        vm.expectRevert(Errors.LockTooLong.selector);
        veELTA.increaseUnlockTime(tooLongEnd);
        vm.stopPrank();
    }

    function test_Withdraw() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);

        // Fast forward past lock end
        vm.warp(block.timestamp + lockDuration + 1);

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, amount);

        veELTA.withdraw();
        vm.stopPrank();

        (uint128 lockAmount,,) = veELTA.locks(user1);
        assertEq(lockAmount, 0);
        assertEq(elta.balanceOf(user1), 10000 ether); // Back to original balance
        assertEq(elta.balanceOf(address(veELTA)), 0);
    }

    function test_RevertWhen_WithdrawNotExpired() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);

        vm.expectRevert(Errors.LockNotExpired.selector);
        veELTA.withdraw();
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawNoActiveLock() public {
        vm.expectRevert(Errors.NoActiveLock.selector);
        vm.prank(user1);
        veELTA.withdraw();
    }

    function test_VotingPower() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks; // 1 year

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);
        vm.stopPrank();

        // At start, voting power should be proportional to lock duration
        uint256 expectedInitialPower = (amount * lockDuration) / veELTA.MAX_LOCK();
        assertEq(veELTA.votingPower(user1), expectedInitialPower);

        // Halfway through, voting power should be ~25% (26 weeks remaining / 104 weeks max)
        vm.warp(block.timestamp + lockDuration / 2);
        uint256 halfwayPower = veELTA.votingPower(user1);
        uint256 expectedPower = (amount * (lockDuration / 2)) / veELTA.MAX_LOCK();
        assertApproxEqRel(halfwayPower, expectedPower, 0.01e18); // 1% tolerance

        // At end, voting power should be 0
        vm.warp(block.timestamp + lockDuration / 2);
        assertEq(veELTA.votingPower(user1), 0);
    }

    function test_VotingPowerNoLock() public {
        assertEq(veELTA.votingPower(user1), 0);
    }

    function test_VotingPowerExpiredLock() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, lockDuration);
        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + lockDuration + 1);
        assertEq(veELTA.votingPower(user1), 0);
    }

    function test_CreateLockAfterExpiry() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount * 2);
        veELTA.createLock(amount, lockDuration);

        // Fast forward past expiry
        vm.warp(block.timestamp + lockDuration + 1);

        // Should be able to create new lock without withdrawing
        veELTA.createLock(amount, lockDuration);
        vm.stopPrank();

        (uint128 lockAmount,,) = veELTA.locks(user1);
        assertEq(lockAmount, amount);
    }

    function testFuzz_CreateLock(uint256 amount, uint256 duration) public {
        amount = bound(amount, 1 ether, 10000 ether);
        duration = bound(duration, veELTA.MIN_LOCK(), veELTA.MAX_LOCK());

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, duration);
        vm.stopPrank();

        (uint128 lockAmount, uint64 start, uint64 end) = veELTA.locks(user1);
        assertEq(lockAmount, amount);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + duration);
    }

    function testFuzz_VotingPowerDecay(uint256 amount, uint256 duration, uint256 timeElapsed)
        public
    {
        amount = bound(amount, 1 ether, 10000 ether);
        duration = bound(duration, veELTA.MIN_LOCK(), veELTA.MAX_LOCK());
        timeElapsed = bound(timeElapsed, 0, duration);

        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        veELTA.createLock(amount, duration);
        vm.stopPrank();

        vm.warp(block.timestamp + timeElapsed);

        uint256 expectedPower = (amount * (duration - timeElapsed)) / veELTA.MAX_LOCK();
        assertEq(veELTA.votingPower(user1), expectedPower);
    }
}
