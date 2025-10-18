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
        // NOTE: RewardsDistributor now requires full architecture - skipping for now
        // Use script/Deploy.sol or test/integration/RevenueFlow.t.sol for full integration tests
        // rewards = new RewardsDistributor(...);
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
        // NOTE: V2 only supports ONE lock per user
        // This test needs to be rewritten for the new architecture
        // See test/unit/VeELTA.t.sol for V2-specific tests

        // Alice creates a single staking position
        vm.startPrank(alice);
        elta.approve(address(staking), 1_500_000 ether);

        // V2 API: lock() instead of createLock(), no tokenId returned
        staking.lock(1_500_000 ether, uint64(block.timestamp + 104 weeks)); // 2 years

        vm.stopPrank();

        // Verify lock created - V2: check veELTA balance
        assertGt(staking.balanceOf(alice), 0); // Has veELTA voting power

        // Check voting power (V2: balanceOf returns voting power)
        uint256 totalVotingPower = staking.balanceOf(alice);
        assertGt(totalVotingPower, 0);

        // NOTE: V2 doesn't support mergePositions (single lock per user)
        // Position management tests moved to test/unit/VeELTA.t.sol
    }

    function _testXPWorkflow() internal {
        // Award XP for various activities
        vm.startPrank(admin);
        xp.award(alice, 5000 ether); // Data submission
        xp.award(bob, 3000 ether); // App usage
        xp.award(charlie, 1500 ether); // Community participation
        vm.stopPrank();

        // Verify XP balances
        assertEq(xp.balanceOf(alice), 5000 ether);
        assertEq(xp.balanceOf(bob), 3000 ether);
        assertEq(xp.balanceOf(charlie), 1500 ether);

        // XP is now permanent (no decay in simplified version)
        // Test that XP persists over time
        vm.warp(block.timestamp + 7 days);
        assertEq(xp.balanceOf(alice), 5000 ether);
        assertEq(xp.balanceOf(bob), 3000 ether);
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
        // NOTE: V2 rewards workflow completely changed
        // - No addRewardToken() - only ELTA
        // - No finalizeEpoch() - no Merkle roots
        // - deposit() auto-splits 70/15/15
        // - Claims via getPastVotes() snapshots
        // See test/integration/RevenueFlow.t.sol for V2-specific tests
    }

    function _testGovernanceWorkflow() internal {
        // Test basic governance functionality without complex execution

        // Verify users have voting power for governance
        uint256 aliceVotes = elta.getVotes(alice);
        uint256 bobVotes = elta.getVotes(bob);

        assertGt(aliceVotes, 0);
        assertGt(bobVotes, 0);

        // Verify governance thresholds
        uint256 proposalThreshold = governor.proposalThreshold();
        uint256 quorum = governor.quorum(block.number - 1);

        assertGt(proposalThreshold, 0);
        assertGt(quorum, 0);

        // Verify users can meet thresholds if needed
        assertGt(aliceVotes, proposalThreshold); // Alice can create proposals

        // Note: Full governance testing would require proper setup
        // This test verifies the governance infrastructure is in place
    }

    function test_SystemCompatibility() public {
        // Test that all systems work together harmoniously

        // 1. Stake ELTA for governance weight
        vm.startPrank(alice);
        elta.approve(address(staking), 1_000_000 ether);
        staking.lock(1_000_000 ether, uint64(block.timestamp + 104 weeks));
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
        assertGt(staking.balanceOf(alice), 0);
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

        // veELTA should not be transferable (ERC20 with transfers disabled)
        vm.startPrank(alice);
        elta.approve(address(staking), 1_000_000 ether);
        staking.lock(1_000_000 ether, uint64(block.timestamp + 52 weeks));

        // V2: Try to transfer veELTA tokens (should revert)
        vm.expectRevert(Errors.NonTransferable.selector);
        staking.transfer(bob, 100 ether);
        vm.stopPrank();
    }
}
