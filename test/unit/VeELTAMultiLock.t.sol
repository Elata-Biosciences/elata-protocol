// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { VeELTAMultiLock } from "../../src/staking/VeELTAMultiLock.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract VeELTAMultiLockTest is Test {
    VeELTAMultiLock public veELTA;
    ELTA public elta;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    event LockCreated(address indexed user, uint256 indexed tokenId, uint256 amount, uint256 start, uint256 end);
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newAmount);
    event LockExtended(uint256 indexed tokenId, uint256 oldEnd, uint256 newEnd);
    event PositionsMerged(uint256 indexed fromTokenId, uint256 indexed toTokenId, uint256 totalAmount);
    event PositionSplit(uint256 indexed originalTokenId, uint256 indexed newTokenId, uint256 splitAmount);
    event VotingPowerDelegated(uint256 indexed tokenId, address indexed from, address indexed to);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        veELTA = new VeELTAMultiLock(elta, admin);
        
        // Give users some ELTA
        vm.startPrank(treasury);
        elta.transfer(user1, 50000 ether);
        elta.transfer(user2, 30000 ether);
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(veELTA.ELTA()), address(elta));
        assertEq(veELTA.name(), "Vote-Escrowed ELTA Multi-Lock");
        assertEq(veELTA.symbol(), "veELTA-ML");
        assertEq(veELTA.MIN_LOCK(), 1 weeks);
        assertEq(veELTA.MAX_LOCK(), 208 weeks);
        assertEq(veELTA.EMERGENCY_UNLOCK_PENALTY(), 5000);
        assertEq(veELTA.nextTokenId(), 1);
        
        assertTrue(veELTA.hasRole(veELTA.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(veELTA.hasRole(veELTA.MANAGER_ROLE(), admin));
        assertTrue(veELTA.hasRole(veELTA.EMERGENCY_ROLE(), admin));
    }

    function test_CreateLock() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;
        
        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        
        vm.expectEmit(true, true, false, true);
        emit LockCreated(user1, 1, amount, block.timestamp, block.timestamp + lockDuration);
        
        uint256 tokenId = veELTA.createLock(amount, lockDuration);
        vm.stopPrank();
        
        assertEq(tokenId, 1);
        assertEq(veELTA.ownerOf(tokenId), user1);
        assertEq(veELTA.balanceOf(user1), 1);
        
        (uint128 lockAmount, uint64 start, uint64 end, address delegate, bool emergencyUnlocked) = 
            veELTA.positions(tokenId);
        
        assertEq(lockAmount, amount);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + lockDuration);
        assertEq(delegate, user1);
        assertFalse(emergencyUnlocked);
        
        // Check voting power
        uint256 expectedVotingPower = (amount * lockDuration) / veELTA.MAX_LOCK();
        assertEq(veELTA.getPositionVotingPower(tokenId), expectedVotingPower);
        assertEq(veELTA.getUserVotingPower(user1), expectedVotingPower);
        assertEq(veELTA.getDelegatedVotingPower(user1), expectedVotingPower);
    }

    function test_CreateMultipleLocks() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 3000 ether);
        
        uint256 tokenId1 = veELTA.createLock(1000 ether, 52 weeks);
        uint256 tokenId2 = veELTA.createLock(1500 ether, 104 weeks);
        uint256 tokenId3 = veELTA.createLock(500 ether, 26 weeks);
        vm.stopPrank();
        
        assertEq(veELTA.balanceOf(user1), 3);
        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(tokenId3, 3);
        
        // Check total voting power
        uint256 totalVotingPower = veELTA.getUserVotingPower(user1);
        assertGt(totalVotingPower, 0);
        
        uint256[] memory positions = veELTA.getUserPositions(user1);
        assertEq(positions.length, 3);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId2);
        assertEq(positions[2], tokenId3);
    }

    function test_IncreaseAmount() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 2000 ether);
        
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        uint256 oldVotingPower = veELTA.getPositionVotingPower(tokenId);
        
        vm.expectEmit(true, false, false, true);
        emit LockIncreased(tokenId, 500 ether, 1500 ether);
        
        veELTA.increaseAmount(tokenId, 500 ether);
        vm.stopPrank();
        
        (uint128 amount,,,, ) = veELTA.positions(tokenId);
        assertEq(amount, 1500 ether);
        
        uint256 newVotingPower = veELTA.getPositionVotingPower(tokenId);
        assertGt(newVotingPower, oldVotingPower);
    }

    function test_IncreaseUnlockTime() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        uint256 oldEnd = block.timestamp + 52 weeks;
        uint256 newEnd = oldEnd + 26 weeks;
        
        vm.expectEmit(true, false, false, true);
        emit LockExtended(tokenId, oldEnd, newEnd);
        
        veELTA.increaseUnlockTime(tokenId, newEnd);
        vm.stopPrank();
        
        (, , uint64 end, , ) = veELTA.positions(tokenId);
        assertEq(end, newEnd);
    }

    function test_MergePositions() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 3000 ether);
        
        uint256 tokenId1 = veELTA.createLock(1000 ether, 52 weeks);
        uint256 tokenId2 = veELTA.createLock(1500 ether, 78 weeks);
        
        vm.expectEmit(true, true, false, true);
        emit PositionsMerged(tokenId1, tokenId2, 2500 ether);
        
        veELTA.mergePositions(tokenId1, tokenId2);
        vm.stopPrank();
        
        // tokenId1 should be burned
        vm.expectRevert();
        veELTA.ownerOf(tokenId1);
        
        // tokenId2 should have combined amount and longer duration
        (uint128 amount, , uint64 end, , ) = veELTA.positions(tokenId2);
        assertEq(amount, 2500 ether);
        assertEq(end, block.timestamp + 78 weeks); // Takes the longer duration
        
        assertEq(veELTA.balanceOf(user1), 1); // Only one position remaining
    }

    function test_SplitPosition() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 2000 ether);
        
        uint256 originalTokenId = veELTA.createLock(2000 ether, 52 weeks);
        uint256 splitAmount = 800 ether;
        
        vm.expectEmit(true, true, false, true);
        emit PositionSplit(originalTokenId, 2, splitAmount);
        
        uint256 newTokenId = veELTA.splitPosition(originalTokenId, splitAmount);
        vm.stopPrank();
        
        assertEq(newTokenId, 2);
        assertEq(veELTA.balanceOf(user1), 2);
        
        // Check original position
        (uint128 originalAmount, , , , ) = veELTA.positions(originalTokenId);
        assertEq(originalAmount, 1200 ether);
        
        // Check new position
        (uint128 newAmount, uint64 start, uint64 end, address delegate, ) = veELTA.positions(newTokenId);
        assertEq(newAmount, splitAmount);
        assertEq(delegate, user1);
        assertEq(end, block.timestamp + 52 weeks);
    }

    function test_DelegatePosition() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        uint256 votingPower = veELTA.getPositionVotingPower(tokenId);
        
        vm.expectEmit(true, true, true, false);
        emit VotingPowerDelegated(tokenId, user1, user2);
        
        veELTA.delegatePosition(tokenId, user2);
        vm.stopPrank();
        
        // Check delegation
        (, , , address delegate, ) = veELTA.positions(tokenId);
        assertEq(delegate, user2);
        assertEq(veELTA.getDelegatedVotingPower(user1), 0);
        assertEq(veELTA.getDelegatedVotingPower(user2), votingPower);
    }

    function test_Withdraw() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        
        // Fast forward past lock end
        vm.warp(block.timestamp + 53 weeks);
        
        uint256 initialBalance = elta.balanceOf(user1);
        
        veELTA.withdraw(tokenId);
        vm.stopPrank();
        
        assertEq(elta.balanceOf(user1), initialBalance + 1000 ether);
        assertEq(veELTA.balanceOf(user1), 0);
        
        // Position should be cleared
        (uint128 amount, , , , ) = veELTA.positions(tokenId);
        assertEq(amount, 0);
    }

    function test_RevertWhen_TransferPosition() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        
        vm.expectRevert(Errors.TransfersDisabled.selector);
        veELTA.transferFrom(user1, user2, tokenId);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateLockInvalidParams() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        
        // Zero amount
        vm.expectRevert(Errors.InvalidAmount.selector);
        veELTA.createLock(0, 52 weeks);
        
        // Too short
        vm.expectRevert(Errors.LockTooShort.selector);
        veELTA.createLock(1000 ether, 6 days);
        
        // Too long
        vm.expectRevert(Errors.LockTooLong.selector);
        veELTA.createLock(1000 ether, 209 weeks);
        
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedOperations() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        vm.stopPrank();
        
        // User2 tries to operate on user1's position
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(user2);
        veELTA.increaseAmount(tokenId, 500 ether);
        
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(user2);
        veELTA.increaseUnlockTime(tokenId, block.timestamp + 104 weeks);
        
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(user2);
        veELTA.withdraw(tokenId);
    }

    function test_VotingPowerDecay() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        
        uint256 tokenId = veELTA.createLock(1000 ether, 104 weeks); // 2 years
        uint256 initialPower = veELTA.getPositionVotingPower(tokenId);
        
        // After 1 year, voting power should be ~50%
        vm.warp(block.timestamp + 52 weeks);
        uint256 halfwayPower = veELTA.getPositionVotingPower(tokenId);
        
        // After 2 years, voting power should be 0
        vm.warp(block.timestamp + 52 weeks);
        uint256 endPower = veELTA.getPositionVotingPower(tokenId);
        
        vm.stopPrank();
        
        assertEq(initialPower, 500 ether); // 104 weeks / 208 weeks = 0.5
        assertApproxEqRel(halfwayPower, 250 ether, 0.01e18); // 52 weeks / 208 weeks = 0.25
        assertEq(endPower, 0);
    }

    function test_EmergencyUnlock() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        vm.stopPrank();
        
        // Enable emergency unlock
        vm.prank(admin);
        veELTA.setEmergencyUnlockEnabled(true);
        
        uint256 initialBalance = elta.balanceOf(user1);
        uint256 expectedReturn = 1000 ether - (1000 ether * 5000) / 10000; // 50% penalty
        
        vm.prank(admin);
        veELTA.emergencyUnlock(tokenId);
        
        assertEq(elta.balanceOf(user1), initialBalance + expectedReturn);
        
        (uint128 amount, , , , bool emergencyUnlocked) = veELTA.positions(tokenId);
        assertEq(amount, 0);
        assertTrue(emergencyUnlocked);
    }

    function test_RevertWhen_EmergencyUnlockDisabled() public {
        vm.startPrank(user1);
        elta.approve(address(veELTA), 1000 ether);
        uint256 tokenId = veELTA.createLock(1000 ether, 52 weeks);
        vm.stopPrank();
        
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(admin);
        veELTA.emergencyUnlock(tokenId);
    }

    function testFuzz_CreateLock(uint256 amount, uint256 duration) public {
        amount = bound(amount, 1 ether, 50000 ether);
        duration = bound(duration, veELTA.MIN_LOCK(), veELTA.MAX_LOCK());
        
        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        
        uint256 tokenId = veELTA.createLock(amount, duration);
        vm.stopPrank();
        
        assertEq(veELTA.ownerOf(tokenId), user1);
        
        (uint128 lockAmount, uint64 start, uint64 end, , ) = veELTA.positions(tokenId);
        assertEq(lockAmount, amount);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + duration);
    }

    function testFuzz_VotingPowerCalculation(uint256 amount, uint256 duration, uint256 timeElapsed) public {
        amount = bound(amount, 1 ether, 10000 ether);
        duration = bound(duration, veELTA.MIN_LOCK(), veELTA.MAX_LOCK());
        timeElapsed = bound(timeElapsed, 0, duration);
        
        vm.startPrank(user1);
        elta.approve(address(veELTA), amount);
        
        uint256 tokenId = veELTA.createLock(amount, duration);
        vm.stopPrank();
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 votingPower = veELTA.getPositionVotingPower(tokenId);
        uint256 expectedPower = (amount * (duration - timeElapsed)) / veELTA.MAX_LOCK();
        
        assertEq(votingPower, expectedPower);
    }
}
