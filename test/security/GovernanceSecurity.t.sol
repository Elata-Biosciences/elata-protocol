// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { ElataGovernor } from "../../src/governance/ElataGovernor.sol";
import { ElataTimelock } from "../../src/governance/ElataTimelock.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { Errors } from "../../src/utils/Errors.sol";

/**
 * @title Governance Security Tests
 * @notice Tests for governance attacks and manipulation
 * @dev Tests proposal manipulation, voting attacks, and governance takeover attempts
 */
contract GovernanceSecurityTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataXP public xp;
    LotPool public funding;
    ElataGovernor public governor;
    TimelockController public timelock;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    
    uint256 public constant TOTAL_SUPPLY = 77_000_000 ether;
    
    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, TOTAL_SUPPLY);
        xp = new ElataXP(admin);
        staking = new VeELTA(elta, admin);
        funding = new LotPool(elta, xp, admin);
        governor = new ElataGovernor(elta);
        
        // Create timelock
        address[] memory proposers = new address[](1);
        proposers[0] = address(governor);
        
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute
        
        timelock = new ElataTimelock(48 hours, proposers, executors, admin);
        
        // Distribute tokens for governance testing
        vm.startPrank(treasury);
        elta.transfer(user1, 5_000_000 ether);  // ~6.5% - above quorum
        elta.transfer(user2, 3_000_000 ether);  // ~3.9% - below quorum alone
        elta.transfer(user3, 1_500_000 ether);  // ~1.9%
        elta.transfer(attacker, 100_000 ether); // ~0.1% - threshold amount
        vm.stopPrank();
        
        // Setup delegation for governance
        vm.prank(user1);
        elta.delegate(user1);
        
        vm.prank(user2);
        elta.delegate(user2);
        
        vm.prank(user3);
        elta.delegate(user3);
        
        vm.prank(attacker);
        elta.delegate(attacker);
    }

    function test_Security_QuorumEnforcement() public {
        // Test that proposals fail without proper quorum
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", attacker, 1_000_000 ether);
        
        // Attacker creates proposal (has just enough for threshold)
        vm.prank(attacker);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Malicious transfer");
        
        // Fast forward past voting delay
        vm.warp(block.timestamp + 1 days + 1);
        
        // Only attacker votes (insufficient for quorum)
        vm.prank(attacker);
        governor.castVote(proposalId, 1); // For
        
        // Fast forward past voting period
        vm.warp(block.timestamp + 7 days + 1);
        
        // Proposal should be defeated due to lack of quorum
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
        
        // Execution should fail
        vm.expectRevert();
        governor.execute(targets, values, calldatas, keccak256(bytes("Malicious transfer")));
    }

    function test_Security_ProposalThresholdEnforcement() public {
        // Test that users below threshold cannot create proposals
        
        address lowBalanceUser = makeAddr("lowBalanceUser");
        vm.prank(treasury);
        elta.transfer(lowBalanceUser, 50_000 ether); // Below 77K threshold
        
        vm.prank(lowBalanceUser);
        elta.delegate(lowBalanceUser);
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", lowBalanceUser, 1000 ether);
        
        // Should fail due to insufficient voting power
        vm.expectRevert();
        vm.prank(lowBalanceUser);
        governor.propose(targets, values, calldatas, "Insufficient threshold proposal");
    }

    function test_Security_EmergencyProposalAbuse() public {
        // Test that emergency proposals require higher threshold
        
        uint256 emergencyThreshold = governor.emergencyProposalThreshold();
        uint256 attackerVotes = elta.getVotes(attacker);
        
        // Verify attacker doesn't have enough for emergency proposal
        assertLt(attackerVotes, emergencyThreshold);
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", attacker, 1_000_000 ether);
        
        // Emergency proposal should fail
        vm.expectRevert();
        vm.prank(attacker);
        governor.proposeEmergency(targets, values, calldatas, "Fake emergency");
    }

    function test_Security_VotingDelayBypass() public {
        // Test that voting delay cannot be bypassed
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", user1, 1000 ether);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");
        
        // Try to vote immediately (should fail)
        vm.expectRevert();
        vm.prank(user1);
        governor.castVote(proposalId, 1);
        
        // Verify proposal is in Pending state
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

    function test_Security_DoubleVotingPrevention() public {
        // Test that users cannot vote twice on the same proposal
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", user1, 1000 ether);
        
        vm.prank(user1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");
        
        // Fast forward past voting delay
        vm.warp(block.timestamp + 1 days + 1);
        
        // First vote
        vm.prank(user1);
        governor.castVote(proposalId, 1); // For
        
        // Try to vote again (should fail)
        vm.expectRevert();
        vm.prank(user1);
        governor.castVote(proposalId, 0); // Against
        
        // Verify only first vote counted
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, elta.getVotes(user1));
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    function test_Security_LotPoolSnapshotManipulation() public {
        // Test that LotPool snapshots cannot be manipulated
        
        // Give user XP
        vm.prank(admin);
        xp.award(user1, 5000 ether);
        
        // Start round (takes snapshot)
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("TEST_PROPOSAL");
        
        address[] memory recipients = new address[](1);
        recipients[0] = user1;
        
        vm.prank(admin);
        (uint256 roundId, uint256 snapshotBlock) = funding.startRound(options, recipients, 7 days);
        
        // User gets more XP after snapshot
        vm.prank(admin);
        xp.award(user1, 10_000 ether);
        
        // User should only be able to vote with XP from snapshot
        vm.prank(user1);
        funding.vote(roundId, options[0], 5000 ether); // Original XP amount
        
        // Try to vote with new XP (should fail)
        vm.expectRevert(Errors.InsufficientXP.selector);
        vm.prank(user1);
        funding.vote(roundId, options[0], 1 ether); // Already used all snapshot XP
        
        // Verify vote was limited to snapshot amount
        assertEq(funding.votesFor(roundId, options[0]), 5000 ether);
    }

    function test_Security_DelegationManipulation() public {
        // Test that delegation cannot be used to manipulate voting
        
        // User1 delegates to user2
        vm.prank(user1);
        elta.delegate(user2);
        
        // User2 now has voting power from both accounts
        uint256 user2VotingPower = elta.getVotes(user2);
        assertEq(user2VotingPower, 3_000_000 ether + 5_000_000 ether); // user2 + user1
        
        // User1 cannot vote anymore (delegated away)
        assertEq(elta.getVotes(user1), 0);
        
        // User1 can reclaim delegation
        vm.prank(user1);
        elta.delegate(user1);
        
        // Voting power should return to user1
        assertEq(elta.getVotes(user1), 5_000_000 ether);
        assertEq(elta.getVotes(user2), 3_000_000 ether);
    }

    function test_Security_StakingPositionManipulation() public {
        // Test that staking positions cannot be manipulated for governance advantage
        
        vm.startPrank(user1);
        elta.approve(address(staking), 1_000_000 ether);
        
        // Create position with minimum lock
        uint256 tokenId1 = staking.createLock(500_000 ether, staking.MIN_LOCK());
        
        // Create position with maximum lock  
        uint256 tokenId2 = staking.createLock(500_000 ether, staking.MAX_LOCK());
        
        uint256 minLockPower = staking.getPositionVotingPower(tokenId1);
        uint256 maxLockPower = staking.getPositionVotingPower(tokenId2);
        
        // Max lock should have significantly more voting power
        assertGt(maxLockPower, minLockPower);
        
        // Verify the exact ratio
        uint256 expectedMinPower = (500_000 ether * staking.MIN_LOCK()) / staking.MAX_LOCK();
        uint256 expectedMaxPower = 500_000 ether; // Full amount for max lock
        
        assertEq(minLockPower, expectedMinPower);
        assertEq(maxLockPower, expectedMaxPower);
        
        vm.stopPrank();
    }

    function testFuzz_Security_GovernanceThresholds(
        uint256 voterBalance,
        uint256 proposalThreshold,
        uint256 quorumThreshold
    ) public {
        // Bound inputs to realistic ranges
        voterBalance = bound(voterBalance, 1 ether, 10_000_000 ether);
        
        // Get actual thresholds from contract
        uint256 actualProposalThreshold = governor.proposalThreshold();
        uint256 actualQuorum = governor.quorum(block.number - 1);
        
        address testUser = makeAddr("testUser");
        vm.prank(treasury);
        elta.transfer(testUser, voterBalance);
        
        vm.prank(testUser);
        elta.delegate(testUser);
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", testUser, 1000 ether);
        
        if (voterBalance >= actualProposalThreshold) {
            // Should be able to create proposal
            vm.prank(testUser);
            uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");
            assertGt(proposalId, 0);
            
            // Fast forward and vote
            vm.warp(block.timestamp + 1 days + 1);
            vm.prank(testUser);
            governor.castVote(proposalId, 1);
            
            // Check if proposal succeeds based on quorum
            vm.warp(block.timestamp + 7 days + 1);
            
            if (voterBalance >= actualQuorum) {
                assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
            } else {
                assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
            }
        } else {
            // Should not be able to create proposal
            vm.expectRevert();
            vm.prank(testUser);
            governor.propose(targets, values, calldatas, "Test proposal");
        }
    }
}
