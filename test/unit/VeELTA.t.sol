// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract VeELTATest is Test {
    VeELTA public staking;
    ELTA public elta;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    event LockCreated(
        address indexed user, uint256 indexed tokenId, uint256 amount, uint256 start, uint256 end
    );
    event LockIncreased(uint256 indexed tokenId, uint256 addedAmount, uint256 newAmount);
    event LockExtended(uint256 indexed tokenId, uint256 oldEnd, uint256 newEnd);
    event PositionsMerged(
        uint256 indexed fromTokenId, uint256 indexed toTokenId, uint256 totalAmount
    );
    event PositionSplit(
        uint256 indexed originalTokenId, uint256 indexed newTokenId, uint256 splitAmount
    );
    event VotingPowerDelegated(uint256 indexed tokenId, address indexed from, address indexed to);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        staking = new VeELTA(elta, admin);

        // Give users some ELTA
        vm.startPrank(treasury);
        elta.transfer(user1, 50_000 ether);
        elta.transfer(user2, 30_000 ether);
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(staking.ELTA()), address(elta));
        assertEq(staking.name(), "Vote-Escrowed ELTA");
        assertEq(staking.symbol(), "veELTA");
        assertEq(staking.MIN_LOCK(), 1 weeks);
        assertEq(staking.MAX_LOCK(), 208 weeks);
        assertEq(staking.EMERGENCY_UNLOCK_PENALTY(), 5000);
        assertEq(staking.nextTokenId(), 1);

        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.MANAGER_ROLE(), admin));
        assertTrue(staking.hasRole(staking.EMERGENCY_ROLE(), admin));
    }

    function test_CreateLock() public {
        uint256 amount = 1000 ether;
        uint256 lockDuration = 52 weeks;

        vm.startPrank(user1);
        elta.approve(address(staking), amount);

        vm.expectEmit(true, true, false, true);
        emit LockCreated(user1, 1, amount, block.timestamp, block.timestamp + lockDuration);

        uint256 tokenId = staking.createLock(amount, lockDuration);
        vm.stopPrank();

        assertEq(tokenId, 1);
        assertEq(staking.ownerOf(tokenId), user1);
        assertEq(staking.balanceOf(user1), 1);

        (uint128 lockAmount, uint64 start, uint64 end, address delegate, bool emergencyUnlocked) =
            staking.positions(tokenId);

        assertEq(lockAmount, amount);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + lockDuration);
        assertEq(delegate, user1);
        assertFalse(emergencyUnlocked);

        // Check voting power
        uint256 expectedVotingPower = (amount * lockDuration) / staking.MAX_LOCK();
        assertEq(staking.getPositionVotingPower(tokenId), expectedVotingPower);
        assertEq(staking.getUserVotingPower(user1), expectedVotingPower);
        assertEq(staking.getDelegatedVotingPower(user1), expectedVotingPower);
    }

    function test_CreateMultipleLocks() public {
        vm.startPrank(user1);
        elta.approve(address(staking), 30_000 ether);

        uint256 tokenId1 = staking.createLock(10_000 ether, 52 weeks);
        uint256 tokenId2 = staking.createLock(15_000 ether, 104 weeks);
        uint256 tokenId3 = staking.createLock(5_000 ether, 26 weeks);
        vm.stopPrank();

        assertEq(staking.balanceOf(user1), 3);
        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(tokenId3, 3);

        // Check total voting power
        uint256 totalVotingPower = staking.getUserVotingPower(user1);
        assertGt(totalVotingPower, 0);

        uint256[] memory positions = staking.getUserPositions(user1);
        assertEq(positions.length, 3);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId2);
        assertEq(positions[2], tokenId3);
    }

    function test_MergePositions() public {
        vm.startPrank(user1);
        elta.approve(address(staking), 30_000 ether);

        uint256 tokenId1 = staking.createLock(10_000 ether, 52 weeks);
        uint256 tokenId2 = staking.createLock(15_000 ether, 78 weeks);

        vm.expectEmit(true, true, false, true);
        emit PositionsMerged(tokenId1, tokenId2, 25_000 ether);

        staking.mergePositions(tokenId1, tokenId2);
        vm.stopPrank();

        // tokenId1 should be burned
        vm.expectRevert();
        staking.ownerOf(tokenId1);

        // tokenId2 should have combined amount and longer duration
        (uint128 amount,, uint64 end,,) = staking.positions(tokenId2);
        assertEq(amount, 25_000 ether);
        assertEq(end, block.timestamp + 78 weeks); // Takes the longer duration

        assertEq(staking.balanceOf(user1), 1); // Only one position remaining
    }

    function test_SplitPosition() public {
        vm.startPrank(user1);
        elta.approve(address(staking), 20_000 ether);

        uint256 originalTokenId = staking.createLock(20_000 ether, 52 weeks);
        uint256 splitAmount = 8_000 ether;

        vm.expectEmit(true, true, false, true);
        emit PositionSplit(originalTokenId, 2, splitAmount);

        uint256 newTokenId = staking.splitPosition(originalTokenId, splitAmount);
        vm.stopPrank();

        assertEq(newTokenId, 2);
        assertEq(staking.balanceOf(user1), 2);

        // Check original position
        (uint128 originalAmount,,,,) = staking.positions(originalTokenId);
        assertEq(originalAmount, 12_000 ether);

        // Check new position
        (uint128 newAmount, uint64 start, uint64 end, address delegate,) =
            staking.positions(newTokenId);
        assertEq(newAmount, splitAmount);
        assertEq(delegate, user1);
        assertEq(end, block.timestamp + 52 weeks);
    }

    function test_DelegatePosition() public {
        vm.startPrank(user1);
        elta.approve(address(staking), 10_000 ether);

        uint256 tokenId = staking.createLock(10_000 ether, 52 weeks);
        uint256 votingPower = staking.getPositionVotingPower(tokenId);

        vm.expectEmit(true, true, true, false);
        emit VotingPowerDelegated(tokenId, user1, user2);

        staking.delegatePosition(tokenId, user2);
        vm.stopPrank();

        // Check delegation
        (,,, address delegate,) = staking.positions(tokenId);
        assertEq(delegate, user2);
        assertEq(staking.getDelegatedVotingPower(user1), 0);
        assertEq(staking.getDelegatedVotingPower(user2), votingPower);
    }

    function test_Withdraw() public {
        vm.startPrank(user1);
        elta.approve(address(staking), 10_000 ether);

        uint256 tokenId = staking.createLock(10_000 ether, 52 weeks);

        // Fast forward past lock end
        vm.warp(block.timestamp + 53 weeks);

        uint256 initialBalance = elta.balanceOf(user1);

        staking.withdraw(tokenId);
        vm.stopPrank();

        assertEq(elta.balanceOf(user1), initialBalance + 10_000 ether);
        assertEq(staking.balanceOf(user1), 0);

        // Position should be cleared
        (uint128 amount,,,,) = staking.positions(tokenId);
        assertEq(amount, 0);
    }

    function test_RevertWhen_TransferPosition() public {
        vm.startPrank(user1);
        elta.approve(address(staking), 10_000 ether);

        uint256 tokenId = staking.createLock(10_000 ether, 52 weeks);

        vm.expectRevert(Errors.TransfersDisabled.selector);
        staking.transferFrom(user1, user2, tokenId);
        vm.stopPrank();
    }

    function testFuzz_CreateLock(uint256 amount, uint256 duration) public {
        amount = bound(amount, 1 ether, 50_000 ether);
        duration = bound(duration, staking.MIN_LOCK(), staking.MAX_LOCK());

        vm.startPrank(user1);
        elta.approve(address(staking), amount);

        uint256 tokenId = staking.createLock(amount, duration);
        vm.stopPrank();

        assertEq(staking.ownerOf(tokenId), user1);

        (uint128 lockAmount, uint64 start, uint64 end,,) = staking.positions(tokenId);
        assertEq(lockAmount, amount);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + duration);
    }
}
