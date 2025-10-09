// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { Errors } from "../../src/utils/Errors.sol";

/**
 * @title Core Security Verification
 * @notice Simple, focused tests to verify core security mechanisms work
 * @dev Tests the most critical security features without complex scenarios
 */
contract CoreSecurityVerificationTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataXP public xp;
    LotPool public funding;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        xp = new ElataXP(admin);
        staking = new VeELTA(elta, admin);
        funding = new LotPool(elta, xp, admin);
    }

    function test_Critical_UnauthorizedMinting() public {
        // Verify attacker cannot mint ELTA
        vm.expectRevert();
        vm.prank(attacker);
        elta.mint(attacker, 1_000_000 ether);

        // Verify balance is still zero
        assertEq(elta.balanceOf(attacker), 0);

        // Verify attacker cannot mint XP
        vm.expectRevert();
        vm.prank(attacker);
        xp.award(attacker, 1_000_000 ether);

        // Verify XP balance is still zero
        assertEq(xp.balanceOf(attacker), 0);
    }

    function test_Critical_SupplyCapEnforcement() public {
        uint256 maxSupply = elta.MAX_SUPPLY();
        uint256 currentSupply = elta.totalSupply();
        uint256 remainingMintable = maxSupply - currentSupply;

        // Admin mints up to cap - should work
        vm.prank(admin);
        elta.mint(user1, remainingMintable);

        assertEq(elta.totalSupply(), maxSupply);

        // Try to mint beyond cap - should fail
        vm.expectRevert(Errors.CapExceeded.selector);
        vm.prank(admin);
        elta.mint(user1, 1);

        // Total supply should remain at cap
        assertEq(elta.totalSupply(), maxSupply);
    }

    function test_Critical_NonTransferableXP() public {
        // Give user some XP
        vm.prank(admin);
        xp.award(user1, 10_000 ether);

        assertEq(xp.balanceOf(user1), 10_000 ether);

        // Try to transfer XP - should fail
        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user1);
        xp.transfer(attacker, 5_000 ether);

        // XP should not have moved
        assertEq(xp.balanceOf(user1), 10_000 ether);
        assertEq(xp.balanceOf(attacker), 0);
    }

    function test_Critical_NonTransferableStakingPositions() public {
        // Give user some ELTA and create position
        vm.prank(treasury);
        elta.transfer(user1, 100_000 ether);

        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        vm.stopPrank();

        // Verify position exists
        assertEq(staking.ownerOf(tokenId), user1);

        // Try to transfer position - should fail
        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user1);
        staking.transferFrom(user1, attacker, tokenId);

        // Position should still belong to user1
        assertEq(staking.ownerOf(tokenId), user1);
    }

    function test_Critical_VotingDoubleSpending() public {
        // Give user XP
        vm.prank(admin);
        xp.award(user1, 1000 ether);

        // Fund the pool
        vm.startPrank(treasury);
        elta.approve(address(funding), 50_000 ether);
        funding.fund(50_000 ether);
        vm.stopPrank();

        // Start round
        vm.roll(block.number + 1);

        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("OPTION_A");
        options[1] = keccak256("OPTION_B");

        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = attacker;

        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);

        // User votes with all XP on option A
        vm.prank(user1);
        funding.vote(roundId, options[0], 1000 ether);

        // Try to vote again - should fail
        vm.expectRevert(Errors.InsufficientXP.selector);
        vm.prank(user1);
        funding.vote(roundId, options[1], 1 ether);

        // Verify only first vote counted
        assertEq(funding.votesFor(roundId, options[0]), 1000 ether);
        assertEq(funding.votesFor(roundId, options[1]), 0);
    }

    function test_Critical_TimeLockEnforcement() public {
        // Give user ELTA and create position
        vm.prank(treasury);
        elta.transfer(user1, 100_000 ether);

        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);

        // Try to withdraw before expiry - should fail
        vm.expectRevert(Errors.LockNotExpired.selector);
        staking.withdraw(tokenId);

        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + 53 weeks);

        // Now withdrawal should work
        vm.prank(user1);
        staking.withdraw(tokenId);

        // Verify position was withdrawn
        (uint128 amount,,,,) = staking.positions(tokenId);
        assertEq(amount, 0);
    }

    function test_Critical_AdminFunctionsWork() public {
        // Verify admin can perform authorized operations

        // Admin can mint ELTA
        vm.prank(admin);
        elta.mint(user1, 1000 ether);
        assertEq(elta.balanceOf(user1), 1000 ether);

        // Admin can award XP
        vm.prank(admin);
        xp.award(user1, 1000 ether);
        assertEq(xp.balanceOf(user1), 1000 ether);

        // Admin can start funding rounds
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("ADMIN_PROPOSAL");

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.roll(block.number + 1);
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);

        assertGt(roundId, 0);
    }

    function test_Critical_VotingPowerCalculation() public {
        // Test that voting power is calculated correctly and cannot be manipulated

        vm.prank(treasury);
        elta.transfer(user1, 1_000_000 ether);

        vm.startPrank(user1);
        elta.approve(address(staking), 1_000_000 ether);

        // Create position with max lock duration
        uint256 tokenId = staking.createLock(1_000_000 ether, staking.MAX_LOCK());

        // Voting power should equal locked amount for max lock
        uint256 votingPower = staking.getPositionVotingPower(tokenId);
        assertEq(votingPower, 1_000_000 ether);

        // Fast forward halfway
        vm.warp(block.timestamp + staking.MAX_LOCK() / 2);

        // Voting power should be approximately half
        uint256 halfwayPower = staking.getPositionVotingPower(tokenId);
        assertApproxEqRel(halfwayPower, 500_000 ether, 0.01e18);

        // Fast forward to expiry
        vm.warp(block.timestamp + staking.MAX_LOCK() / 2);

        // Voting power should be zero
        uint256 expiredPower = staking.getPositionVotingPower(tokenId);
        assertEq(expiredPower, 0);

        vm.stopPrank();
    }

    function test_Critical_XPDecayMechanism() public {
        // Test that XP is permanent (no decay in simplified version)

        vm.prank(admin);
        xp.award(user1, 10_000 ether);

        // Balance remains constant over time
        assertEq(xp.balanceOf(user1), 10_000 ether);

        // After 7 days, balance should still be the same
        vm.warp(block.timestamp + 7 days);
        assertEq(xp.balanceOf(user1), 10_000 ether);

        // After 14 days, balance should still be the same
        vm.warp(block.timestamp + 7 days);
        assertEq(xp.balanceOf(user1), 10_000 ether);

        // XP is permanent until explicitly revoked
    }

    function test_Critical_EmergencyMechanisms() public {
        // Test emergency mechanisms work correctly

        vm.prank(treasury);
        elta.transfer(user1, 100_000 ether);

        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        vm.stopPrank();

        // Emergency unlock should be disabled by default
        assertFalse(staking.emergencyUnlockEnabled());

        // Try emergency unlock when disabled - should fail
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(admin);
        staking.emergencyUnlock(tokenId);

        // Enable emergency unlock
        vm.prank(admin);
        staking.setEmergencyUnlockEnabled(true);
        assertTrue(staking.emergencyUnlockEnabled());

        // Now emergency unlock should work
        uint256 initialBalance = elta.balanceOf(user1);
        vm.prank(admin);
        staking.emergencyUnlock(tokenId);

        // Should receive 50% (penalty applied)
        uint256 expectedReturn = 100_000 ether - (100_000 ether * 5000) / 10000;
        assertEq(elta.balanceOf(user1), initialBalance + expectedReturn);
    }
}
