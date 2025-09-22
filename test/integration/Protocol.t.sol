// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { ElataGovernor } from "../../src/governance/ElataGovernor.sol";

/**
 * @title Protocol Integration Test
 * @notice Comprehensive integration tests for the complete Elata Protocol
 * @dev Tests end-to-end workflows and cross-contract interactions
 */
contract ProtocolTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataXP public xp;
    LotPool public funding;
    RewardsDistributor public rewards;
    ElataGovernor public governor;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public researcher1 = makeAddr("researcher1");
    address public researcher2 = makeAddr("researcher2");
    
    uint256 public constant TOTAL_SUPPLY = 77_000_000 ether;
    uint256 public constant INITIAL_MINT = 10_000_000 ether;

    function setUp() public {
        // Deploy complete protocol
        elta = new ELTA("ELTA", "ELTA", admin, treasury, INITIAL_MINT, TOTAL_SUPPLY);
        xp = new ElataXP(admin);
        staking = new VeELTA(elta, admin);
        funding = new LotPool(elta, xp, admin);
        rewards = new RewardsDistributor(staking, admin);
        governor = new ElataGovernor(elta);
        
        // Distribute tokens for testing (treasury has 10M, distribute 8M)
        vm.startPrank(treasury);
        elta.transfer(alice, 4_000_000 ether);
        elta.transfer(bob, 2_500_000 ether);
        elta.transfer(charlie, 1_500_000 ether);
        vm.stopPrank();
        
        // Setup governance delegation
        vm.prank(alice);
        elta.delegate(alice);
        
        vm.prank(bob);
        elta.delegate(bob);
        
        vm.prank(charlie);
        elta.delegate(charlie);
    }

    function test_CompleteProtocolWorkflow() public {
        // 1. Users create staking positions
        _testStakingWorkflow();
        
        // 2. Users earn and spend XP
        _testXPWorkflow();
        
        // 3. Community funding rounds
        _testFundingWorkflow();
        
        // 4. Rewards distribution
        _testRewardsWorkflow();
        
        // 5. Governance participation
        _testGovernanceWorkflow();
    }

    function _testStakingWorkflow() internal {
        // Alice creates multiple staking positions
        vm.startPrank(alice);
        elta.approve(address(staking), 3_500_000 ether);
        
        uint256 tokenId1 = staking.createLock(1_500_000 ether, 104 weeks); // 2 years
        uint256 tokenId2 = staking.createLock(1_000_000 ether, 52 weeks);  // 1 year
        uint256 tokenId3 = staking.createLock(1_000_000 ether, 26 weeks);  // 6 months
        
        vm.stopPrank();
        
        // Verify positions created
        assertEq(staking.balanceOf(alice), 3);
        
        uint256[] memory positions = staking.getUserPositions(alice);
        assertEq(positions.length, 3);
        assertEq(positions[0], tokenId1);
        assertEq(positions[1], tokenId2);
        assertEq(positions[2], tokenId3);
        
        // Check total voting power
        uint256 totalVotingPower = staking.getUserVotingPower(alice);
        assertGt(totalVotingPower, 0);
        
        // Test position management
        vm.prank(alice);
        staking.mergePositions(tokenId2, tokenId1); // Merge into longer position
        
        assertEq(staking.balanceOf(alice), 2);
    }

    function _testXPWorkflow() internal {
        // Award XP for various activities
        vm.startPrank(admin);
        xp.award(alice, 5000 ether);   // Data submission
        xp.award(bob, 3000 ether);     // App usage
        xp.award(charlie, 1500 ether); // Community participation
        vm.stopPrank();
        
        // Verify XP balances
        assertEq(xp.balanceOf(alice), 5000 ether);
        assertEq(xp.balanceOf(bob), 3000 ether);
        assertEq(xp.balanceOf(charlie), 1500 ether);
        
        // Test XP decay over time
        vm.warp(block.timestamp + 7 days);
        
        uint256 aliceEffective = xp.effectiveBalance(alice);
        assertLt(aliceEffective, 5000 ether); // Should be ~2500 due to decay
        assertGt(aliceEffective, 2000 ether);
        
        // Apply decay
        xp.updateUserDecay(alice);
        assertApproxEqRel(xp.balanceOf(alice), aliceEffective, 0.01e18);
    }

    function _testFundingWorkflow() internal {
        // Ensure users have XP for voting
        vm.startPrank(admin);
        xp.award(alice, 3000 ether);
        xp.award(bob, 2000 ether);
        vm.stopPrank();
        
        // Fund the pool
        vm.startPrank(treasury);
        elta.approve(address(funding), 100_000 ether);
        funding.fund(100_000 ether);
        vm.stopPrank();
        
        // Advance block for XP snapshot
        vm.roll(block.number + 1);
        
        // Start funding round
        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("PTSD_RESEARCH");
        options[1] = keccak256("DEPRESSION_STUDY");
        
        address[] memory recipients = new address[](2);
        recipients[0] = researcher1;
        recipients[1] = researcher2;
        
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        // Users vote with their XP
        vm.prank(alice);
        funding.vote(roundId, options[0], 2500 ether); // PTSD research
        
        vm.prank(bob);
        funding.vote(roundId, options[1], 1800 ether); // Depression study
        
        // Verify votes
        assertEq(funding.votesFor(roundId, options[0]), 2500 ether);
        assertEq(funding.votesFor(roundId, options[1]), 1800 ether);
        
        // Finalize round
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(admin);
        funding.finalize(roundId, options[0], 50_000 ether); // PTSD research wins
        
        // Verify payout
        assertEq(elta.balanceOf(researcher1), 50_000 ether);
    }

    function _testRewardsWorkflow() internal {
        // Setup rewards system
        vm.prank(admin);
        rewards.addRewardToken(elta);
        
        // Deposit rewards
        vm.startPrank(treasury);
        elta.approve(address(rewards), 100_000 ether);
        
        vm.stopPrank();
        
        vm.prank(admin);
        rewards.grantRole(rewards.DISTRIBUTOR_ROLE(), treasury);
        
        vm.prank(treasury);
        rewards.depositRewards(address(elta), 100_000 ether);
        
        // Fast forward and finalize epoch
        vm.warp(block.timestamp + 8 days);
        
        bytes32 merkleRoot = keccak256("rewards_epoch_1");
        vm.prank(treasury);
        rewards.finalizeEpoch(merkleRoot);
        
        // Verify epoch finalized
        (,,,, bool finalized) = rewards.getCurrentEpoch();
        assertTrue(finalized);
    }

    function _testGovernanceWorkflow() internal {
        // Create governance proposal
        address[] memory targets = new address[](1);
        targets[0] = address(xp);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "grantRole(bytes32,address)", 
            xp.XP_MINTER_ROLE(), 
            address(funding)
        );
        
        string memory description = "Grant XP minter role to funding system";
        
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        
        // Fast forward past voting delay
        vm.warp(block.timestamp + 1 days + 1);
        
        // Vote on proposal
        vm.prank(alice);
        governor.castVote(proposalId, 1); // For
        
        vm.prank(bob);
        governor.castVote(proposalId, 1); // For
        
        // Verify voting
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
        assertEq(againstVotes, 0);
        
        // Fast forward past voting period
        vm.warp(block.timestamp + 7 days + 1);
        
        // Proposal should be successful
        // Note: Execution would require proper timelock setup in production
    }

    function test_SystemCompatibility() public {
        // Test that all systems work together harmoniously
        
        // 1. Stake ELTA for governance weight
        vm.startPrank(alice);
        elta.approve(address(staking), 1_000_000 ether);
        staking.createLock(1_000_000 ether, 104 weeks);
        vm.stopPrank();
        
        // 2. Earn XP through participation
        vm.prank(admin);
        xp.award(alice, 2000 ether);
        
        // 3. Use XP for funding votes
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("INTEGRATION_TEST");
        
        address[] memory recipients = new address[](1);
        recipients[0] = researcher1;
        
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        vm.prank(alice);
        funding.vote(roundId, options[0], 1500 ether);
        
        // 4. Verify all systems are working
        assertGt(staking.getUserVotingPower(alice), 0);
        assertGt(xp.balanceOf(alice), 0);
        assertEq(funding.votesFor(roundId, options[0]), 1500 ether);
        assertGt(elta.getVotes(alice), 0); // Governance voting power
    }

    function test_AccessControl() public {
        // Verify proper access control across all contracts
        
        // Token access control
        vm.expectRevert();
        vm.prank(alice);
        elta.mint(alice, 1000 ether);
        
        // XP access control
        vm.expectRevert();
        vm.prank(alice);
        xp.award(alice, 1000 ether);
        
        // Funding access control
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("UNAUTHORIZED_TEST");
        
        address[] memory recipients = new address[](1);
        recipients[0] = researcher1;
        
        vm.expectRevert();
        vm.prank(alice);
        funding.startRound(options, recipients, 7 days);
    }

    function test_TokenTransferability() public {
        // ELTA should be transferable
        vm.prank(alice);
        elta.transfer(bob, 1000 ether);
        assertEq(elta.balanceOf(bob), 2_500_000 ether + 1000 ether);
        
        // XP should not be transferable
        vm.prank(admin);
        xp.award(alice, 1000 ether);
        
        vm.expectRevert();
        vm.prank(alice);
        xp.transfer(bob, 500 ether);
        
        // Staking positions should not be transferable
        vm.startPrank(alice);
        elta.approve(address(staking), 1_000_000 ether);
        uint256 tokenId = staking.createLock(1_000_000 ether, 52 weeks);
        
        vm.expectRevert();
        staking.transferFrom(alice, bob, tokenId);
        vm.stopPrank();
    }
}
