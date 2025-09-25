// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { LpLocker } from "../../src/apps/LpLocker.sol";
import { IUniswapV2Pair } from "../../src/interfaces/IUniswapV2Pair.sol";

// Mock LP token for testing
contract MockLpToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract LpLockerTest is Test {
    LpLocker public locker;
    MockLpToken public lpToken;

    address public beneficiary = makeAddr("beneficiary");
    address public user1 = makeAddr("user1");

    uint256 public constant APP_ID = 1;
    uint256 public constant LOCK_DURATION = 365 days * 2; // 2 years
    uint256 public unlockTime;

    event LpLocked(
        uint256 indexed appId,
        address lpToken,
        address beneficiary,
        uint256 unlockAt,
        uint256 amount
    );
    event LpClaimed(uint256 indexed appId, address beneficiary, uint256 amount);

    function setUp() public {
        lpToken = new MockLpToken();
        unlockTime = block.timestamp + LOCK_DURATION;

        locker = new LpLocker(APP_ID, address(lpToken), beneficiary, unlockTime);

        // Mint some LP tokens for testing
        lpToken.mint(address(this), 1000 ether);
        lpToken.mint(user1, 500 ether);
    }

    function test_Deployment() public {
        assertEq(locker.appId(), APP_ID);
        assertEq(locker.lpToken(), address(lpToken));
        assertEq(locker.beneficiary(), beneficiary);
        assertEq(locker.unlockAt(), unlockTime);
        assertFalse(locker.claimed());
    }

    function test_RevertWhen_DeploymentInvalidParams() public {
        vm.expectRevert("Zero LP token");
        new LpLocker(APP_ID, address(0), beneficiary, unlockTime);

        vm.expectRevert("Zero beneficiary");
        new LpLocker(APP_ID, address(lpToken), address(0), unlockTime);

        vm.expectRevert("Invalid unlock time");
        new LpLocker(APP_ID, address(lpToken), beneficiary, block.timestamp - 1);
    }

    function test_LockLp() public {
        uint256 lockAmount = 100 ether;

        // Transfer LP tokens to locker
        lpToken.transfer(address(locker), lockAmount);

        vm.expectEmit(true, true, true, true);
        emit LpLocked(APP_ID, address(lpToken), beneficiary, unlockTime, lockAmount);

        locker.lockLp(lockAmount);

        assertEq(locker.getLockedBalance(), lockAmount);
    }

    function test_RevertWhen_LockZeroAmount() public {
        vm.expectRevert("Zero amount");
        locker.lockLp(0);
    }

    function test_CanClaim() public {
        // Initially cannot claim (not unlocked)
        assertFalse(locker.canClaim());

        // Fast forward to unlock time
        vm.warp(unlockTime + 1);

        // Now can claim
        assertTrue(locker.canClaim());
    }

    function test_TimeUntilUnlock() public {
        uint256 timeRemaining = locker.timeUntilUnlock();
        assertEq(timeRemaining, LOCK_DURATION);

        // Fast forward halfway
        vm.warp(block.timestamp + LOCK_DURATION / 2);
        timeRemaining = locker.timeUntilUnlock();
        assertApproxEqAbs(timeRemaining, LOCK_DURATION / 2, 1);

        // Fast forward past unlock
        vm.warp(unlockTime + 1);
        timeRemaining = locker.timeUntilUnlock();
        assertEq(timeRemaining, 0);
    }

    function test_Claim() public {
        uint256 lockAmount = 100 ether;

        // Lock some LP tokens
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        // Fast forward to unlock time
        vm.warp(unlockTime + 1);

        uint256 beneficiaryBefore = lpToken.balanceOf(beneficiary);

        vm.expectEmit(true, true, true, true);
        emit LpClaimed(APP_ID, beneficiary, lockAmount);

        vm.prank(beneficiary);
        locker.claim();

        uint256 beneficiaryAfter = lpToken.balanceOf(beneficiary);
        assertEq(beneficiaryAfter - beneficiaryBefore, lockAmount);
        assertEq(locker.getLockedBalance(), 0);
        assertTrue(locker.claimed());
    }

    function test_RevertWhen_ClaimTooEarly() public {
        uint256 lockAmount = 100 ether;
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        vm.expectRevert(LpLocker.NotYetUnlocked.selector);
        vm.prank(beneficiary);
        locker.claim();
    }

    function test_RevertWhen_ClaimUnauthorized() public {
        uint256 lockAmount = 100 ether;
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        vm.warp(unlockTime + 1);

        vm.expectRevert(LpLocker.Unauthorized.selector);
        vm.prank(user1);
        locker.claim();
    }

    function test_RevertWhen_ClaimTwice() public {
        uint256 lockAmount = 100 ether;
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        vm.warp(unlockTime + 1);

        // First claim succeeds
        vm.prank(beneficiary);
        locker.claim();

        // Second claim fails
        vm.expectRevert(LpLocker.AlreadyClaimed.selector);
        vm.prank(beneficiary);
        locker.claim();
    }

    function test_GetLockedBalance() public {
        assertEq(locker.getLockedBalance(), 0);

        uint256 lockAmount = 250 ether;
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        assertEq(locker.getLockedBalance(), lockAmount);

        // Add more LP tokens
        uint256 additionalAmount = 150 ether;
        lpToken.transfer(address(locker), additionalAmount);
        locker.lockLp(additionalAmount);

        assertEq(locker.getLockedBalance(), lockAmount + additionalAmount);
    }

    function testFuzz_LockAndClaim(uint256 lockAmount, uint256 timeOffset) public {
        lockAmount = bound(lockAmount, 1 ether, 1000 ether);
        timeOffset = bound(timeOffset, 0, 365 days * 5); // Up to 5 years

        // Mint LP tokens to this contract
        lpToken.mint(address(this), lockAmount);

        // Lock LP tokens
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        assertEq(locker.getLockedBalance(), lockAmount);

        // Fast forward
        vm.warp(block.timestamp + timeOffset);

        if (timeOffset >= LOCK_DURATION) {
            // Should be able to claim
            assertTrue(locker.canClaim());

            vm.prank(beneficiary);
            locker.claim();

            assertEq(lpToken.balanceOf(beneficiary), lockAmount);
            assertTrue(locker.claimed());
        } else {
            // Should not be able to claim yet
            assertFalse(locker.canClaim());

            vm.expectRevert(LpLocker.NotYetUnlocked.selector);
            vm.prank(beneficiary);
            locker.claim();
        }
    }

    function test_MultipleDepositsBeforeClaim() public {
        // Lock LP tokens in multiple transactions
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;
        uint256 amount3 = 50 ether;

        lpToken.transfer(address(locker), amount1);
        locker.lockLp(amount1);

        lpToken.transfer(address(locker), amount2);
        locker.lockLp(amount2);

        lpToken.transfer(address(locker), amount3);
        locker.lockLp(amount3);

        uint256 totalLocked = amount1 + amount2 + amount3;
        assertEq(locker.getLockedBalance(), totalLocked);

        // Fast forward and claim all
        vm.warp(unlockTime + 1);

        vm.prank(beneficiary);
        locker.claim();

        assertEq(lpToken.balanceOf(beneficiary), totalLocked);
    }

    function test_LockDurationEdgeCases() public {
        // Test exactly at unlock time
        uint256 lockAmount = 100 ether;
        lpToken.transfer(address(locker), lockAmount);
        locker.lockLp(lockAmount);

        // One second before unlock
        vm.warp(unlockTime - 1);
        assertFalse(locker.canClaim());

        vm.expectRevert(LpLocker.NotYetUnlocked.selector);
        vm.prank(beneficiary);
        locker.claim();

        // Exactly at unlock time
        vm.warp(unlockTime);
        assertTrue(locker.canClaim());

        vm.prank(beneficiary);
        locker.claim();

        assertEq(lpToken.balanceOf(beneficiary), lockAmount);
    }
}
