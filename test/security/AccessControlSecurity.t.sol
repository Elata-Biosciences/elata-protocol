// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { ElataGovernor } from "../../src/governance/ElataGovernor.sol";
import { Errors } from "../../src/utils/Errors.sol";

/**
 * @title Access Control Security Tests
 * @notice Comprehensive tests for access control vulnerabilities
 * @dev Tests privilege escalation, role management, and unauthorized access
 */
contract AccessControlSecurityTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataXP public xp;
    LotPool public funding;
    RewardsDistributor public rewards;
    ElataGovernor public governor;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        xp = new ElataXP(admin);
        staking = new VeELTA(elta, admin);
        funding = new LotPool(elta, xp, admin);
        rewards = new RewardsDistributor(staking, admin);
        governor = new ElataGovernor(elta);
    }

    function test_Security_UnauthorizedMinting() public {
        // Attacker tries to mint ELTA without MINTER_ROLE
        vm.expectRevert();
        vm.prank(attacker);
        elta.mint(attacker, 1_000_000 ether);
        
        // Attacker tries to mint XP without XP_MINTER_ROLE
        vm.expectRevert();
        vm.prank(attacker);
        xp.award(attacker, 1_000_000 ether);
        
        // Verify balances remain zero
        assertEq(elta.balanceOf(attacker), 0);
        assertEq(xp.balanceOf(attacker), 0);
    }

    function test_Security_RoleEscalationAttempts() public {
        // Attacker tries to grant themselves admin role
        vm.expectRevert();
        vm.prank(attacker);
        elta.grantRole(elta.DEFAULT_ADMIN_ROLE(), attacker);
        
        // Attacker tries to grant themselves minter role
        vm.expectRevert();
        vm.prank(attacker);
        elta.grantRole(elta.MINTER_ROLE(), attacker);
        
        // Attacker tries to grant themselves XP minter role
        vm.expectRevert();
        vm.prank(attacker);
        xp.grantRole(xp.XP_MINTER_ROLE(), attacker);
        
        // Attacker tries to grant themselves funding manager role
        vm.expectRevert();
        vm.prank(attacker);
        funding.grantRole(funding.MANAGER_ROLE(), attacker);
        
        // Verify attacker has no roles
        assertFalse(elta.hasRole(elta.DEFAULT_ADMIN_ROLE(), attacker));
        assertFalse(elta.hasRole(elta.MINTER_ROLE(), attacker));
        assertFalse(xp.hasRole(xp.XP_MINTER_ROLE(), attacker));
        assertFalse(funding.hasRole(funding.MANAGER_ROLE(), attacker));
    }

    function test_Security_UnauthorizedFundingOperations() public {
        // Attacker tries to start funding round
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("MALICIOUS_PROPOSAL");
        
        address[] memory recipients = new address[](1);
        recipients[0] = attacker;
        
        vm.expectRevert();
        vm.prank(attacker);
        funding.startRound(options, recipients, 7 days);
        
        // Setup legitimate round for next test
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        // Attacker tries to finalize round early
        vm.expectRevert();
        vm.prank(attacker);
        funding.finalize(roundId, options[0], 10_000 ether);
        
        // Attacker tries to finalize with wrong winner
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert();
        vm.prank(attacker);
        funding.finalize(roundId, keccak256("FAKE_WINNER"), 10_000 ether);
    }

    function test_Security_UnauthorizedStakingOperations() public {
        // Give user1 some ELTA and create a position
        vm.prank(treasury);
        elta.transfer(user1, 10_000 ether);
        
        vm.startPrank(user1);
        elta.approve(address(staking), 10_000 ether);
        uint256 tokenId = staking.createLock(10_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Attacker tries to increase someone else's position
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(attacker);
        staking.increaseAmount(tokenId, 1000 ether);
        
        // Attacker tries to extend someone else's lock
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(attacker);
        staking.increaseUnlockTime(tokenId, block.timestamp + 104 weeks);
        
        // Attacker tries to withdraw someone else's position
        vm.warp(block.timestamp + 53 weeks);
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(attacker);
        staking.withdraw(tokenId);
        
        // Attacker tries to delegate someone else's position
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(attacker);
        staking.delegatePosition(tokenId, attacker);
    }

    function test_Security_UnauthorizedRewardsOperations() public {
        // Attacker tries to add reward token
        vm.expectRevert();
        vm.prank(attacker);
        rewards.addRewardToken(elta);
        
        // Attacker tries to deposit rewards
        vm.expectRevert();
        vm.prank(attacker);
        rewards.depositRewards(address(elta), 1000 ether);
        
        // Attacker tries to finalize epoch
        vm.expectRevert();
        vm.prank(attacker);
        rewards.finalizeEpoch(keccak256("fake_root"));
        
        // Attacker tries to pause system
        vm.expectRevert();
        vm.prank(attacker);
        rewards.setPaused(true);
    }

    function test_Security_EmergencyUnlockAbuse() public {
        // Give user1 some ELTA and create a position
        vm.prank(treasury);
        elta.transfer(user1, 10_000 ether);
        
        vm.startPrank(user1);
        elta.approve(address(staking), 10_000 ether);
        uint256 tokenId = staking.createLock(10_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Attacker tries to emergency unlock without role
        vm.expectRevert();
        vm.prank(attacker);
        staking.emergencyUnlock(tokenId);
        
        // Attacker tries to enable emergency unlock
        vm.expectRevert();
        vm.prank(attacker);
        staking.setEmergencyUnlockEnabled(true);
        
        // Even admin can't emergency unlock when disabled
        vm.expectRevert(Errors.NotAuthorized.selector);
        vm.prank(admin);
        staking.emergencyUnlock(tokenId);
    }

    function test_Security_RoleRevocationSafety() public {
        address tempAdmin = makeAddr("tempAdmin");
        
        // Admin grants role to temp admin
        vm.prank(admin);
        elta.grantRole(elta.MINTER_ROLE(), tempAdmin);
        
        // Temp admin can mint
        vm.prank(tempAdmin);
        elta.mint(user1, 1000 ether);
        assertEq(elta.balanceOf(user1), 1000 ether);
        
        // Admin revokes role
        vm.prank(admin);
        elta.revokeRole(elta.MINTER_ROLE(), tempAdmin);
        
        // Temp admin can no longer mint
        vm.expectRevert();
        vm.prank(tempAdmin);
        elta.mint(user1, 1000 ether);
        
        // Balance should remain unchanged
        assertEq(elta.balanceOf(user1), 1000 ether);
    }

    function test_Security_AdminRoleRenunciation() public {
        // Admin can renounce their own role
        vm.prank(admin);
        elta.renounceRole(elta.DEFAULT_ADMIN_ROLE(), admin);
        
        // Admin should no longer have admin role
        assertFalse(elta.hasRole(elta.DEFAULT_ADMIN_ROLE(), admin));
        
        // Admin can no longer grant roles
        vm.expectRevert();
        vm.prank(admin);
        elta.grantRole(elta.MINTER_ROLE(), user1);
        
        // System should still function for existing roles
        vm.prank(admin); // Still has MINTER_ROLE
        elta.mint(user1, 1000 ether);
        assertEq(elta.balanceOf(user1), 1000 ether);
    }

    function test_Security_CrossContractRoleIsolation() public {
        // Having admin role in one contract shouldn't grant privileges in another
        
        // Admin in ELTA contract
        assertTrue(elta.hasRole(elta.DEFAULT_ADMIN_ROLE(), admin));
        
        // But admin can't directly call protected functions in other contracts without proper setup
        // This is by design - each contract has its own access control
        
        // Verify proper role setup
        assertTrue(xp.hasRole(xp.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(funding.hasRole(funding.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(rewards.hasRole(rewards.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_Security_ZeroAddressProtection() public {
        // Test all contracts reject zero addresses in critical functions
        
        // ELTA
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        elta.mint(address(0), 1000 ether);
        
        // XP
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        xp.award(address(0), 1000 ether);
        
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        xp.revoke(address(0), 1000 ether);
        
        // Staking delegation
        vm.prank(treasury);
        elta.transfer(user1, 10_000 ether);
        
        vm.startPrank(user1);
        elta.approve(address(staking), 10_000 ether);
        uint256 tokenId = staking.createLock(10_000 ether, 52 weeks);
        
        vm.expectRevert(Errors.ZeroAddress.selector);
        staking.delegatePosition(tokenId, address(0));
        vm.stopPrank();
    }

    function testFuzz_Security_RoleBasedAccess(address randomUser, uint256 amount) public {
        // Bound inputs
        vm.assume(randomUser != admin && randomUser != address(0));
        amount = bound(amount, 1, 1_000_000 ether);
        
        // Random user should not be able to mint ELTA
        vm.expectRevert();
        vm.prank(randomUser);
        elta.mint(randomUser, amount);
        
        // Random user should not be able to award XP
        vm.expectRevert();
        vm.prank(randomUser);
        xp.award(randomUser, amount);
        
        // Verify no unauthorized access
        assertEq(elta.balanceOf(randomUser), 0);
        assertEq(xp.balanceOf(randomUser), 0);
    }

    function test_Security_RoleHierarchy() public {
        // Test that roles have proper hierarchy and can't be bypassed
        
        // Create a user with MINTER_ROLE but not DEFAULT_ADMIN_ROLE
        address minter = makeAddr("minter");
        vm.prank(admin);
        elta.grantRole(elta.MINTER_ROLE(), minter);
        
        // Minter can mint but can't grant roles
        vm.prank(minter);
        elta.mint(user1, 1000 ether);
        assertEq(elta.balanceOf(user1), 1000 ether);
        
        vm.expectRevert();
        vm.prank(minter);
        elta.grantRole(elta.MINTER_ROLE(), attacker);
        
        // Verify attacker still has no roles
        assertFalse(elta.hasRole(elta.MINTER_ROLE(), attacker));
    }
}
