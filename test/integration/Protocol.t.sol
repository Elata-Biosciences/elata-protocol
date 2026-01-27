// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElataPoints} from "../../src/experience/ElataPoints.sol";
import {ElataGovernor} from "../../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../../src/governance/ElataTimelock.sol";
import {RewardsDistributor} from "../../src/rewards/RewardsDistributor.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "forge-std/Test.sol";

/**
 * @title Protocol Integration Test
 * @notice Comprehensive integration tests for the complete Elata Protocol
 * @dev Tests end-to-end workflows and cross-contract interactions
 */
contract ProtocolTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataPoints public xp;
    RewardsDistributor public rewards;
    ElataGovernor public governor;
    ElataTimelock public timelock;

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
        elta = new ELTA(treasury);
        xp = new ElataPoints(admin);
        staking = new VeELTA(elta, admin);

        // Deploy governance (timelock + governor using veELTA for voting)
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Anyone can propose through governor
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay
        timelock = new ElataTimelock(48 hours, proposers, executors, admin);
        governor = new ElataGovernor(IVotes(address(staking)), address(timelock));

        // NOTE: RewardsDistributor now requires full architecture - skipping for now
        // Use script/Deploy.sol or test/integration/RevenueFlow.t.sol for full integration tests
        // rewards = new RewardsDistributor(...);

        // Distribute tokens for testing (treasury has 10M, distribute 8M)
        vm.startPrank(treasury);
        elta.transfer(alice, 4_000_000 ether);
        elta.transfer(bob, 2_500_000 ether);
        elta.transfer(charlie, 1_500_000 ether);
        vm.stopPrank();

        // NOTE: ELTA no longer has ERC20Votes - voting power comes from veELTA
        // Users must stake ELTA in veELTA to participate in governance
    }

    function test_CompleteProtocolWorkflow() public {
        // 1. Users create staking positions
        _testStakingWorkflow();

        // 2. Users earn and spend XP
        _testXPWorkflow();

        // 3. Rewards distribution
        _testRewardsWorkflow();

        // 4. Governance participation
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
        // NOTE: Governor now uses veELTA for voting, so users need to have staked
        // Alice already staked in _testStakingWorkflow()

        // Roll forward to create block history for getPastTotalSupply
        vm.roll(block.number + 1);

        // Verify Alice has veELTA voting power for governance (from staking workflow)
        uint256 aliceVotes = staking.getVotes(alice);
        assertGt(aliceVotes, 0);

        // Verify governance thresholds
        uint256 proposalThreshold = governor.proposalThreshold();
        uint256 quorum = governor.quorum(block.number - 1);

        assertGt(proposalThreshold, 0);
        assertGt(quorum, 0);

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

        // 3. Verify all systems are working
        assertGt(staking.balanceOf(alice), 0);
        assertGt(xp.balanceOf(alice), 0);
        assertGt(staking.getVotes(alice), 0); // Governance voting power comes from veELTA
    }

    function test_AccessControl() public {
        // Verify proper access control across all contracts

        // ELTA is a simple ERC20 - no special roles, anyone with tokens can transfer
        // So we test that someone WITHOUT tokens cannot transfer
        address noTokenUser = makeAddr("noTokenUser");
        vm.expectRevert();
        vm.prank(noTokenUser);
        elta.transfer(alice, 1000 ether);

        // XP access control - only admin/operator can award
        vm.expectRevert();
        vm.prank(alice);
        xp.award(alice, 1000 ether);

        // VeELTA access control - admin can manage roles
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), alice));
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
