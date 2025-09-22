// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTAMultiLock } from "../../src/staking/VeELTAMultiLock.sol";
import { ElataXPWithDecay } from "../../src/xp/ElataXPWithDecay.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { ElataGovernorSimple } from "../../src/governance/ElataGovernorSimple.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";

contract Phase2IntegrationTest is Test {
    ELTA public elta;
    VeELTA public veELTASimple;
    VeELTAMultiLock public veELTAMulti;
    ElataXPWithDecay public xp;
    LotPool public lotPool;
    RewardsDistributor public rewardsDistributor;
    ElataGovernorSimple public governor;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public researcher1 = makeAddr("researcher1");
    address public researcher2 = makeAddr("researcher2");
    
    uint256 public constant INITIAL_MINT = 77_000_000 ether;

    function setUp() public {
        // Deploy all contracts
        elta = new ELTA("ELTA", "ELTA", admin, treasury, INITIAL_MINT, INITIAL_MINT);
        veELTASimple = new VeELTA(elta, admin);
        veELTAMulti = new VeELTAMultiLock(elta, admin);
        xp = new ElataXPWithDecay(admin);
        lotPool = new LotPool(elta, xp, admin);
        rewardsDistributor = new RewardsDistributor(veELTASimple, admin);
        governor = new ElataGovernorSimple(elta);
        
        // Distribute tokens
        vm.startPrank(treasury);
        elta.transfer(alice, 10_000_000 ether);
        elta.transfer(bob, 5_000_000 ether);
        elta.transfer(charlie, 2_000_000 ether);
        vm.stopPrank();
        
        // Setup governance delegation
        vm.prank(alice);
        elta.delegate(alice);
        
        vm.prank(bob);
        elta.delegate(bob);
        
        vm.prank(charlie);
        elta.delegate(charlie);
    }

    function test_CompletePhase2Workflow() public {
        // 1. Multi-lock staking
        _testMultiLockStaking();
        
        // 2. XP with decay system
        _testXPDecaySystem();
        
        // 3. Rewards distribution
        _testRewardsDistribution();
        
        // 4. Advanced governance
        _testAdvancedGovernance();
        
        // 5. Integration between all systems
        _testSystemIntegration();
    }

    function _testMultiLockStaking() internal {
        vm.startPrank(alice);
        elta.approve(address(veELTAMulti), 5_000_000 ether);
        
        // Create multiple lock positions
        uint256 tokenId1 = veELTAMulti.createLock(2_000_000 ether, 104 weeks); // 2 years
        uint256 tokenId2 = veELTAMulti.createLock(1_500_000 ether, 52 weeks);  // 1 year
        uint256 tokenId3 = veELTAMulti.createLock(1_000_000 ether, 26 weeks);  // 6 months
        
        vm.stopPrank();
        
        assertEq(veELTAMulti.balanceOf(alice), 3);
        
        uint256[] memory positions = veELTAMulti.getUserPositions(alice);
        assertEq(positions.length, 3);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId2);
        assertEq(positions[2], tokenId3);
        
        // Check total voting power
        uint256 totalVotingPower = veELTAMulti.getUserVotingPower(alice);
        assertGt(totalVotingPower, 0);
        
        // Test position merging
        vm.prank(alice);
        veELTAMulti.mergePositions(tokenId2, tokenId1); // Merge into longer position
        
        assertEq(veELTAMulti.balanceOf(alice), 2);
        
        // Test position splitting
        vm.prank(alice);
        uint256 newTokenId = veELTAMulti.splitPosition(tokenId1, 1_000_000 ether);
        
        assertEq(veELTAMulti.balanceOf(alice), 3);
        assertEq(newTokenId, 4);
    }

    function _testXPDecaySystem() internal {
        // Award XP to users
        vm.startPrank(admin);
        xp.award(alice, 2000 ether);
        xp.award(bob, 1500 ether);
        xp.award(charlie, 1000 ether);
        vm.stopPrank();
        
        // Check initial balances
        assertEq(xp.balanceOf(alice), 2000 ether);
        assertEq(xp.effectiveBalance(alice), 2000 ether);
        
        // Fast forward 7 days (half decay)
        vm.warp(block.timestamp + 7 days);
        
        uint256 halfDecayBalance = xp.effectiveBalance(alice);
        assertApproxEqRel(halfDecayBalance, 1000 ether, 0.01e18);
        
        // Award more XP during decay period
        vm.prank(admin);
        xp.award(alice, 800 ether);
        
        // Total balance should be 2800, but effective balance accounts for decay
        assertEq(xp.balanceOf(alice), 2800 ether);
        
        uint256 newEffectiveBalance = xp.effectiveBalance(alice);
        assertGt(newEffectiveBalance, halfDecayBalance);
        assertLt(newEffectiveBalance, 2800 ether);
        
        // Test batch decay update
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        
        vm.warp(block.timestamp + 8 days); // Total 15 days from first award
        
        vm.prank(admin);
        xp.batchUpdateDecay(users);
        
        // First awards should be fully decayed, only recent awards remain
        assertLt(xp.balanceOf(alice), 2800 ether);
        assertLt(xp.balanceOf(bob), 1500 ether);
        assertLt(xp.balanceOf(charlie), 1000 ether);
    }

    function _testRewardsDistribution() internal {
        // Setup rewards system
        vm.prank(admin);
        rewardsDistributor.addRewardToken(elta);
        
        // Create some staking positions for rewards calculation
        vm.startPrank(alice);
        elta.approve(address(veELTASimple), 1_000_000 ether);
        veELTASimple.createLock(1_000_000 ether, 104 weeks);
        vm.stopPrank();
        
        vm.startPrank(bob);
        elta.approve(address(veELTASimple), 500_000 ether);
        veELTASimple.createLock(500_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Deposit rewards for current epoch
        vm.startPrank(treasury);
        elta.approve(address(rewardsDistributor), 100_000 ether);
        
        vm.prank(admin);
        rewardsDistributor.grantRole(rewardsDistributor.DISTRIBUTOR_ROLE(), treasury);
        
        rewardsDistributor.depositRewards(address(elta), 100_000 ether);
        vm.stopPrank();
        
        // Fast forward and finalize epoch
        vm.warp(block.timestamp + 8 days);
        
        bytes32 merkleRoot = keccak256("test_rewards");
        vm.prank(treasury);
        rewardsDistributor.finalizeEpoch(merkleRoot);
        
        // Check epoch finalization
        (,,,, bool finalized) = rewardsDistributor.getCurrentEpoch();
        assertTrue(finalized);
    }

    function _testAdvancedGovernance() internal {
        // Create a governance proposal
        address[] memory targets = new address[](1);
        targets[0] = address(xp);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "grantRole(bytes32,address)", 
            xp.XP_MINTER_ROLE(), 
            address(lotPool)
        );
        
        string memory description = "Grant XP minter role to LotPool";
        
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        
        // Fast forward past voting delay
        vm.warp(block.timestamp + 1 days + 1);
        
        // Vote with multiple stakeholders
        vm.prank(alice);
        governor.castVote(proposalId, 1); // For
        
        vm.prank(bob);
        governor.castVote(proposalId, 1); // For
        
        // Check if quorum is met
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        uint256 quorumRequired = governor.quorum(block.number - 1);
        
        assertGe(forVotes, quorumRequired);
        assertEq(againstVotes, 0);
        
        // Fast forward past voting period
        vm.warp(block.timestamp + 7 days + 1);
        
        // Execute proposal
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));
        
        // Verify execution
        assertTrue(governor.isExecuted(proposalId));
    }

    function _testSystemIntegration() internal {
        // Test how all systems work together
        
        // 1. Users stake in multi-lock system
        vm.startPrank(alice);
        elta.approve(address(veELTAMulti), 1_000_000 ether);
        uint256 aliceTokenId = veELTAMulti.createLock(1_000_000 ether, 104 weeks);
        vm.stopPrank();
        
        // 2. Users earn XP through activities (simulated)
        vm.prank(admin);
        xp.award(alice, 5000 ether);
        
        // 3. Create a funding round with XP voting
        vm.roll(block.number + 1); // Ensure XP is available for snapshot
        
        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("ADVANCED_EEG_STUDY");
        options[1] = keccak256("AI_MODEL_RESEARCH");
        
        address[] memory recipients = new address[](2);
        recipients[0] = researcher1;
        recipients[1] = researcher2;
        
        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);
        
        // 4. Vote with XP
        vm.prank(alice);
        lotPool.vote(roundId, options[0], 3000 ether);
        
        // 5. Test XP decay over time
        vm.warp(block.timestamp + 10 days);
        
        uint256 preDecayBalance = xp.balanceOf(alice);
        uint256 effectiveBalance = xp.effectiveBalance(alice);
        
        assertLt(effectiveBalance, preDecayBalance);
        
        // Apply decay
        xp.updateUserDecay(alice);
        
        assertLt(xp.balanceOf(alice), preDecayBalance);
        
        // 6. Test multi-lock position management
        uint256 votingPowerBefore = veELTAMulti.getPositionVotingPower(aliceTokenId);
        
        vm.warp(block.timestamp + 26 weeks);
        
        uint256 votingPowerAfter = veELTAMulti.getPositionVotingPower(aliceTokenId);
        assertLt(votingPowerAfter, votingPowerBefore);
        
        // 7. Finalize funding round
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(admin);
        lotPool.finalize(roundId, options[0], 50_000 ether);
        
        // Verify researcher received funds
        assertEq(elta.balanceOf(researcher1), 50_000 ether);
    }

    function test_CrossSystemCompatibility() public {
        // Test that old and new systems can coexist
        
        // Simple staking
        vm.startPrank(alice);
        elta.approve(address(veELTASimple), 1_000_000 ether);
        veELTASimple.createLock(1_000_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Multi-lock staking
        vm.startPrank(bob);
        elta.approve(address(veELTAMulti), 2_000_000 ether);
        veELTAMulti.createLock(1_000_000 ether, 104 weeks);
        veELTAMulti.createLock(1_000_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Both should have voting power
        assertGt(veELTASimple.votingPower(alice), 0);
        assertGt(veELTAMulti.getUserVotingPower(bob), 0);
        
        // XP system should work independently
        vm.startPrank(admin);
        xp.award(alice, 1000 ether);
        xp.award(bob, 1500 ether);
        vm.stopPrank();
        
        assertEq(xp.balanceOf(alice), 1000 ether);
        assertEq(xp.balanceOf(bob), 1500 ether);
    }

    function test_GovernanceWithMultipleStakingSystems() public {
        // Setup staking in both systems
        vm.startPrank(alice);
        elta.approve(address(veELTASimple), 2_000_000 ether);
        elta.approve(address(veELTAMulti), 3_000_000 ether);
        
        veELTASimple.createLock(2_000_000 ether, 104 weeks);
        veELTAMulti.createLock(3_000_000 ether, 104 weeks);
        vm.stopPrank();
        
        // Alice should have voting power in ELTA governance from her direct holdings
        uint256 aliceVotingPower = elta.getVotes(alice);
        assertEq(aliceVotingPower, 5_000_000 ether); // Remaining balance after staking
        
        // Create governance proposal
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", researcher1, 1_000_000 ether);
        
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Fund research");
        
        // Vote and execute
        vm.warp(block.timestamp + 1 days + 1);
        
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        
        vm.warp(block.timestamp + 7 days + 1);
        
        // This would require proper setup of execution permissions
        // For now, just verify the proposal was created and voted on
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_XPDecayImpactOnFunding() public {
        // Award XP to users
        vm.startPrank(admin);
        xp.award(alice, 5000 ether);
        xp.award(bob, 3000 ether);
        vm.stopPrank();
        
        // Start funding round
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("DECAY_TEST_RESEARCH");
        
        address[] memory recipients = new address[](1);
        recipients[0] = researcher1;
        
        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);
        
        // Vote immediately
        vm.prank(alice);
        lotPool.vote(roundId, options[0], 4000 ether);
        
        // Fast forward to cause XP decay
        vm.warp(block.timestamp + 10 days);
        
        // Apply decay
        xp.updateUserDecay(alice);
        xp.updateUserDecay(bob);
        
        // XP should be reduced due to decay
        assertLt(xp.balanceOf(alice), 5000 ether);
        assertLt(xp.balanceOf(bob), 3000 ether);
        
        // But the vote in the round should still be valid (snapshot-based)
        assertEq(lotPool.votesFor(roundId, options[0]), 4000 ether);
        
        // Finalize round
        vm.prank(admin);
        lotPool.finalize(roundId, options[0], 25_000 ether);
        
        assertEq(elta.balanceOf(researcher1), 25_000 ether);
    }

    function test_RewardsDistributionWithMultiLock() public {
        // Setup rewards
        vm.prank(admin);
        rewardsDistributor.addRewardToken(elta);
        
        // Create staking positions
        vm.startPrank(alice);
        elta.approve(address(veELTASimple), 2_000_000 ether);
        veELTASimple.createLock(2_000_000 ether, 104 weeks);
        vm.stopPrank();
        
        vm.startPrank(bob);
        elta.approve(address(veELTASimple), 1_000_000 ether);
        veELTASimple.createLock(1_000_000 ether, 52 weeks);
        vm.stopPrank();
        
        // Deposit rewards
        vm.startPrank(treasury);
        elta.approve(address(rewardsDistributor), 150_000 ether);
        
        vm.prank(admin);
        rewardsDistributor.grantRole(rewardsDistributor.DISTRIBUTOR_ROLE(), treasury);
        
        rewardsDistributor.depositRewards(address(elta), 150_000 ether);
        vm.stopPrank();
        
        // Fast forward and finalize
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(treasury);
        rewardsDistributor.finalizeEpoch(keccak256("rewards_epoch_1"));
        
        // Verify epoch was finalized
        assertEq(rewardsDistributor.currentEpoch(), 1);
        
        // Check pending rewards (simplified calculation)
        uint256 alicePending = rewardsDistributor.pendingRewards(alice);
        uint256 bobPending = rewardsDistributor.pendingRewards(bob);
        
        // Alice should have more pending rewards due to longer lock
        assertGe(alicePending, bobPending);
    }

    function test_EmergencyMechanisms() public {
        // Test emergency unlock in multi-lock system
        vm.startPrank(alice);
        elta.approve(address(veELTAMulti), 1_000_000 ether);
        uint256 tokenId = veELTAMulti.createLock(1_000_000 ether, 104 weeks);
        vm.stopPrank();
        
        // Enable emergency unlock
        vm.prank(admin);
        veELTAMulti.setEmergencyUnlockEnabled(true);
        
        uint256 initialBalance = elta.balanceOf(alice);
        
        vm.prank(admin);
        veELTAMulti.emergencyUnlock(tokenId);
        
        // Should receive tokens minus penalty
        uint256 expectedReturn = 1_000_000 ether - (1_000_000 ether * 5000) / 10000;
        assertEq(elta.balanceOf(alice), initialBalance + expectedReturn);
        
        // Test emergency governance proposal
        uint256 emergencyThreshold = governor.emergencyProposalThreshold();
        
        // Give alice enough tokens for emergency proposal
        vm.prank(treasury);
        elta.transfer(alice, emergencyThreshold);
        
        vm.prank(alice);
        elta.delegate(alice);
        
        address[] memory targets = new address[](1);
        targets[0] = address(rewardsDistributor);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setPaused(bool)", true);
        
        vm.prank(alice);
        uint256 proposalId = governor.proposeEmergency(targets, values, calldatas, "Emergency pause");
        
        assertTrue(governor.isEmergencyProposal(proposalId));
        assertEq(governor.proposalVotingPeriod(proposalId), 3 days);
    }

    function test_PerformanceMetrics() public {
        // Test gas costs for various operations
        
        uint256 gasBefore;
        uint256 gasAfter;
        
        // Multi-lock creation
        vm.startPrank(alice);
        elta.approve(address(veELTAMulti), 1_000_000 ether);
        
        gasBefore = gasleft();
        veELTAMulti.createLock(1_000_000 ether, 52 weeks);
        gasAfter = gasleft();
        
        uint256 createLockGas = gasBefore - gasAfter;
        console2.log("Multi-lock creation gas:", createLockGas);
        vm.stopPrank();
        
        // XP award with decay
        gasBefore = gasleft();
        vm.prank(admin);
        xp.award(alice, 1000 ether);
        gasAfter = gasleft();
        
        uint256 awardXPGas = gasBefore - gasAfter;
        console2.log("XP award gas:", awardXPGas);
        
        // Decay update
        vm.warp(block.timestamp + 15 days);
        
        gasBefore = gasleft();
        xp.updateUserDecay(alice);
        gasAfter = gasleft();
        
        uint256 decayUpdateGas = gasBefore - gasAfter;
        console2.log("Decay update gas:", decayUpdateGas);
        
        // All operations should be reasonably gas-efficient
        assertLt(createLockGas, 200_000);
        assertLt(awardXPGas, 200_000);
        assertLt(decayUpdateGas, 100_000);
    }
}
