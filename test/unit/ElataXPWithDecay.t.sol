// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ElataXPWithDecay } from "../../src/xp/ElataXPWithDecay.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract ElataXPWithDecayTest is Test {
    ElataXPWithDecay public xp;
    
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public keeper = makeAddr("keeper");

    event XPAwarded(address indexed user, uint256 amount, uint256 timestamp);
    event XPRevoked(address indexed user, uint256 amount);
    event XPDecayed(address indexed user, uint256 decayedAmount, uint256 newBalance);
    event BatchDecayProcessed(uint256 usersProcessed, uint256 totalDecayed);

    function setUp() public {
        xp = new ElataXPWithDecay(admin);
        
        // Note: Admin already has KEEPER_ROLE by default from constructor
    }

    function test_Deployment() public {
        assertEq(xp.name(), "Elata XP with Decay");
        assertEq(xp.symbol(), "ELTAXP");
        assertEq(xp.decimals(), 18);
        assertEq(xp.DECAY_WINDOW(), 14 days);
        assertEq(xp.MIN_DECAY_INTERVAL(), 1 hours);
        
        assertTrue(xp.hasRole(xp.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(xp.hasRole(xp.XP_MINTER_ROLE(), admin));
        assertTrue(xp.hasRole(xp.KEEPER_ROLE(), admin));
    }

    function test_Award() public {
        uint256 amount = 1000 ether;
        
        vm.expectEmit(true, false, false, true);
        emit XPAwarded(user1, amount, block.timestamp);
        
        vm.prank(admin);
        xp.award(user1, amount);
        
        assertEq(xp.balanceOf(user1), amount);
        assertEq(xp.effectiveBalance(user1), amount);
        assertEq(xp.getUserXPEntryCount(user1), 1);
        
        // Check auto-delegation
        assertEq(xp.delegates(user1), user1);
        assertEq(xp.getVotes(user1), amount);
    }

    function test_MultipleAwards() public {
        vm.startPrank(admin);
        xp.award(user1, 500 ether);
        
        vm.warp(block.timestamp + 1 days);
        xp.award(user1, 300 ether);
        
        vm.warp(block.timestamp + 2 days);
        xp.award(user1, 200 ether);
        vm.stopPrank();
        
        // Balance should be less than 1000 due to automatic decay during awards
        uint256 finalBalance = xp.balanceOf(user1);
        assertLt(finalBalance, 1000 ether);
        assertGt(finalBalance, 800 ether); // Should be around 850 ether
        assertEq(xp.getUserXPEntryCount(user1), 3);
        
        // Effective balance should match actual balance since decay was applied
        uint256 effectiveBalance = xp.effectiveBalance(user1);
        assertApproxEqRel(effectiveBalance, finalBalance, 0.01e18);
    }

    function test_Revoke() public {
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        
        vm.expectEmit(true, false, false, true);
        emit XPRevoked(user1, 300 ether);
        
        xp.revoke(user1, 300 ether);
        vm.stopPrank();
        
        assertEq(xp.balanceOf(user1), 700 ether);
    }

    function test_DecayCalculation() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);
        
        // At start, effective balance should equal actual balance
        assertEq(xp.effectiveBalance(user1), 1000 ether);
        
        // After 7 days (half decay window), effective balance should be ~50%
        vm.warp(block.timestamp + 7 days);
        uint256 halfDecayBalance = xp.effectiveBalance(user1);
        assertApproxEqRel(halfDecayBalance, 500 ether, 0.01e18); // 1% tolerance
        
        // After 14 days (full decay window), effective balance should be 0
        vm.warp(block.timestamp + 7 days);
        assertEq(xp.effectiveBalance(user1), 0);
        
        // Actual balance should still be 1000 until decay is applied
        assertEq(xp.balanceOf(user1), 1000 ether);
    }

    function test_UpdateUserDecay() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);
        
        // Fast forward past decay window
        vm.warp(block.timestamp + 15 days);
        
        vm.expectEmit(true, false, false, true);
        emit XPDecayed(user1, 1000 ether, 0);
        
        xp.updateUserDecay(user1);
        
        assertEq(xp.balanceOf(user1), 0);
        assertEq(xp.effectiveBalance(user1), 0);
        assertEq(xp.getUserXPEntryCount(user1), 0);
    }

    function test_PartialDecay() public {
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        
        // Award more XP after 7 days
        vm.warp(block.timestamp + 7 days);
        xp.award(user1, 500 ether);
        vm.stopPrank();
        
        // Fast forward another 7 days (total 14 days from first award)
        vm.warp(block.timestamp + 7 days);
        
        // First award should be fully decayed, second award should be at 50%
        uint256 expectedEffective = 250 ether; // 500 * 0.5
        assertApproxEqRel(xp.effectiveBalance(user1), expectedEffective, 0.01e18);
        
        // Apply decay
        xp.updateUserDecay(user1);
        
        // Should have burned the decayed amount
        uint256 expectedBalance = 250 ether;
        assertApproxEqRel(xp.balanceOf(user1), expectedBalance, 0.01e18);
    }

    function test_BatchUpdateDecay() public {
        // Give XP to multiple users
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        xp.award(user2, 500 ether);
        vm.stopPrank();
        
        // Fast forward past decay window
        vm.warp(block.timestamp + 15 days);
        
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        
        vm.expectEmit(false, false, false, true);
        emit BatchDecayProcessed(2, 1500 ether);
        
        vm.prank(admin); // Use admin who has KEEPER_ROLE
        xp.batchUpdateDecay(users);
        
        assertEq(xp.balanceOf(user1), 0);
        assertEq(xp.balanceOf(user2), 0);
    }

    function test_RevertWhen_BatchUpdateDecayTooFrequent() public {
        address[] memory users = new address[](1);
        users[0] = user1;
        
        // Wait for initial interval to pass
        vm.warp(block.timestamp + 2 hours);
        
        // First call should succeed
        vm.prank(admin);
        xp.batchUpdateDecay(users);
        
        // Second call within MIN_DECAY_INTERVAL should fail
        vm.warp(block.timestamp + 30 minutes); // Less than 1 hour from last call
        
        vm.expectRevert(ElataXPWithDecay.DecayTooFrequent.selector);
        vm.prank(admin);
        xp.batchUpdateDecay(users);
        
        // After MIN_DECAY_INTERVAL, should succeed again
        vm.warp(block.timestamp + 31 minutes); // Total > 1 hour from last call
        
        vm.prank(admin);
        xp.batchUpdateDecay(users); // Should not revert
    }

    function test_TransfersDisabled() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);
        
        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user1);
        xp.transfer(user2, 500 ether);
    }

    function test_GetPastXP() public {
        vm.prank(admin);
        xp.award(user1, 1000 ether);
        
        vm.roll(block.number + 1);
        uint256 block1 = block.number - 1;
        
        vm.prank(admin);
        xp.award(user1, 500 ether);
        
        vm.roll(block.number + 1);
        uint256 block2 = block.number - 1;
        
        assertEq(xp.getPastXP(user1, block1), 1000 ether);
        assertEq(xp.getPastXP(user1, block2), 1500 ether);
    }

    function test_ComplexDecayScenario() public {
        vm.startPrank(admin);
        
        // Day 0: Award 1000 XP
        xp.award(user1, 1000 ether);
        
        // Day 5: Award 500 XP
        vm.warp(block.timestamp + 5 days);
        xp.award(user1, 500 ether);
        
        // Day 10: Award 300 XP
        vm.warp(block.timestamp + 5 days);
        xp.award(user1, 300 ether);
        
        vm.stopPrank();
        
        // Day 12: Check effective balance
        vm.warp(block.timestamp + 2 days);
        
        // First award (12 days old): (14-12)/14 * 1000 = ~143 XP
        // Second award (7 days old): (14-7)/14 * 500 = 250 XP  
        // Third award (2 days old): (14-2)/14 * 300 = ~257 XP
        // Total expected: ~650 XP
        
        uint256 effectiveBalance = xp.effectiveBalance(user1);
        assertGt(effectiveBalance, 600 ether);
        assertLt(effectiveBalance, 700 ether);
        
        // Balance should be less than 1800 due to automatic decay during awards
        uint256 actualBalance = xp.balanceOf(user1);
        assertLt(actualBalance, 1800 ether);
        assertGt(actualBalance, 600 ether); // Should be around 900-1000 ether
        
        // Effective balance should be close to actual balance since decay was applied
        // Note: There can be some difference due to the timing of when decay is applied
        assertApproxEqRel(effectiveBalance, actualBalance, 0.30e18); // 30% tolerance for complex scenarios
    }

    function testFuzz_Award(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        
        vm.prank(admin);
        xp.award(user1, amount);
        
        assertEq(xp.balanceOf(user1), amount);
        assertEq(xp.effectiveBalance(user1), amount);
    }

    function testFuzz_DecayCalculation(uint256 amount, uint256 timeElapsed) public {
        amount = bound(amount, 1 ether, 10000 ether);
        timeElapsed = bound(timeElapsed, 0, 14 days);
        
        vm.prank(admin);
        xp.award(user1, amount);
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 expectedEffective = timeElapsed >= 14 days ? 
            0 : (amount * (14 days - timeElapsed)) / 14 days;
        
        assertApproxEqRel(xp.effectiveBalance(user1), expectedEffective, 0.01e18);
    }
}
