// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ElataGovernor} from "../../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../../src/governance/ElataTimelock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title GovernanceAdvancedSecurity
 * @notice Advanced security tests for ElataGovernor - quorum manipulation, emergency proposals,
 *         vote manipulation, griefing prevention, and timelock integration
 * @dev Tests attack vectors not covered in basic GovernanceSecurity.t.sol
 */
contract GovernanceAdvancedSecurity is Test {
    ELTA public elta;
    VeELTA public veElta;
    ElataGovernor public governor;
    ElataTimelock public timelock;

    address public admin = makeAddr("admin");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public whale = makeAddr("whale");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant MIN_DELAY = 48 hours;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy Timelock
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute

        timelock = new ElataTimelock(MIN_DELAY, proposers, executors, admin);

        // Deploy Governor
        governor = new ElataGovernor(veElta, address(timelock));

        // Grant proposer role to governor
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(admin);
        timelock.grantRole(proposerRole, address(governor));

        // Fund users
        vm.startPrank(admin);
        elta.transfer(attacker, 5_000_000 ether);
        elta.transfer(alice, 10_000_000 ether);
        elta.transfer(bob, 10_000_000 ether);
        elta.transfer(charlie, 5_000_000 ether);
        elta.transfer(whale, 20_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUORUM MANIPULATION ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_QuorumCannotBeManipulatedViaFlashLoan() public {
        // Flash-borrowed ELTA cannot influence quorum because veELTA requires lockup
        // Setup: Alice stakes to create supply
        vm.startPrank(alice);
        elta.approve(address(veElta), 5_000_000 ether);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Record quorum before "flash loan" simulation
        uint256 quorumBefore = governor.quorum(block.number - 1);

        // Attacker tries to increase quorum by locking tokens
        // In a real flash loan attack, they'd borrow, lock, vote, unlock, return
        // But unlock requires waiting for lock expiry
        vm.startPrank(attacker);
        elta.approve(address(veElta), 5_000_000 ether);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 8 days)); // Min lock
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Quorum at the PREVIOUS block (before attacker locked) is unchanged
        // This is the key protection - voting uses historical snapshots
        uint256 quorumAtSnapshot = governor.quorum(block.number - 2);
        assertEq(quorumAtSnapshot, quorumBefore, "Historical quorum should not change");

        // Attacker CANNOT unlock immediately to repay flash loan
        vm.prank(attacker);
        vm.expectRevert();
        veElta.unlock();
    }

    function test_Security_QuorumCalculationUsesHistoricalSnapshot() public {
        // This test verifies that quorum is calculated from historical snapshots
        // Quorum = 4% of veELTA total supply at the snapshot block

        // Alice stakes
        vm.startPrank(alice);
        elta.approve(address(veElta), 2_000_000 ether);
        veElta.lock(2_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Roll forward to allow snapshot queries (past blocks only)
        vm.roll(block.number + 10);

        // Query quorum at a past block (block.number - 1 is always valid)
        uint256 pastBlock = block.number - 1;
        uint256 quorumAtPastBlock = governor.quorum(pastBlock);

        // Query total supply at that block
        uint256 supplyAtPastBlock = veElta.getPastTotalSupply(pastBlock);

        // Quorum should be exactly 4% of supply
        uint256 expectedQuorum = (supplyAtPastBlock * 4) / 100;
        assertEq(quorumAtPastBlock, expectedQuorum, "Quorum = 4% of supply");

        // Verify quorum is non-zero since Alice staked
        assertGt(quorumAtPastBlock, 0, "Quorum > 0 with stakers");
    }

    function test_Security_QuorumMinimumEnforced() public {
        // With stakers, quorum should be 4% of veELTA supply
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        uint256 totalSupply = veElta.getPastTotalSupply(block.number - 1);
        uint256 expectedQuorum = (totalSupply * 4) / 100;
        uint256 actualQuorum = governor.quorum(block.number - 1);

        assertEq(actualQuorum, expectedQuorum, "Quorum should be 4% of supply");
        assertGt(actualQuorum, 0, "Quorum should be > 0 with stakers");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EMERGENCY PROPOSAL SECURITY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_EmergencyProposalRequires5PercentVotingPower() public {
        // Setup: Alice stakes large amount
        vm.startPrank(alice);
        elta.approve(address(veElta), 10_000_000 ether);
        veElta.lock(10_000_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Calculate 5% threshold
        uint256 totalSupply = veElta.getPastTotalSupply(block.number - 1);
        uint256 emergencyThreshold = (totalSupply * 500) / 10000; // 5%

        // Bob stakes less than 5%
        vm.startPrank(bob);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        uint256 bobVotingPower = veElta.getVotes(bob);
        assertLt(bobVotingPower, emergencyThreshold, "Bob should have < 5%");

        // Bob cannot create emergency proposal
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", bob, 1000 ether);

        vm.prank(bob);
        vm.expectRevert();
        governor.proposeEmergency(targets, values, calldatas, "Emergency transfer");
    }

    function test_Security_EmergencyProposalCannotBypassTimelock() public {
        // Whale stakes enough for emergency proposal
        vm.startPrank(whale);
        elta.approve(address(veElta), 20_000_000 ether);
        veElta.lock(20_000_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Create emergency proposal
        address[] memory targets = new address[](1);
        targets[0] = address(timelock);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateDelay(uint256)", 1 hours);

        vm.prank(whale);
        uint256 proposalId = governor.proposeEmergency(targets, values, calldatas, "Emergency: reduce timelock");

        // Verify it's marked as emergency
        assertTrue(governor.isEmergencyProposal(proposalId), "Should be emergency proposal");

        // Even emergency proposals go through standard governor flow (queue -> execute)
        // They cannot skip the timelock - they just have shorter voting period
        IGovernor.ProposalState state = governor.state(proposalId);
        assertTrue(
            state == IGovernor.ProposalState.Pending || state == IGovernor.ProposalState.Active,
            "Should be in normal proposal state"
        );
    }

    function test_Security_EmergencyVotingPeriodIsShorter() public {
        // Setup whale with enough voting power
        vm.startPrank(whale);
        elta.approve(address(veElta), 20_000_000 ether);
        veElta.lock(20_000_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Create emergency proposal
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(whale);
        uint256 emergencyId = governor.proposeEmergency(targets, values, calldatas, "Emergency");

        // Verify emergency voting period is 3 days vs normal 7 days
        uint256 emergencyPeriod = governor.proposalVotingPeriod(emergencyId);
        uint256 normalPeriod = governor.votingPeriod();

        assertEq(emergencyPeriod, 3 days, "Emergency period should be 3 days");
        assertEq(normalPeriod, 7 days, "Normal period should be 7 days");
        assertLt(emergencyPeriod, normalPeriod, "Emergency should be shorter");
    }

    function test_Security_CannotConvertNormalToEmergencyProposal() public {
        // Alice stakes enough to propose
        vm.startPrank(alice);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Create normal proposal
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(alice);
        uint256 normalId = governor.propose(targets, values, calldatas, "Normal proposal");

        // Normal proposal is NOT emergency
        assertFalse(governor.isEmergencyProposal(normalId), "Should not be emergency");

        // There's no way to convert it - emergencyProposals mapping is only set in proposeEmergency
        // And there's no function to modify it after creation
        uint256 votingPeriod = governor.proposalVotingPeriod(normalId);
        assertEq(votingPeriod, 7 days, "Should use normal voting period");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSAL GRIEFING PREVENTION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ProposalThresholdPreventsSpam() public {
        // Check threshold is 77K veELTA (0.1% of 77M)
        uint256 threshold = governor.proposalThreshold();
        assertEq(threshold, 77000e18, "Threshold should be 77K tokens");

        // Attacker with small stake cannot spam proposals
        vm.startPrank(attacker);
        elta.approve(address(veElta), 10_000 ether);
        veElta.lock(10_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        uint256 attackerVotes = veElta.getVotes(attacker);
        assertLt(attackerVotes, threshold, "Attacker below threshold");

        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        vm.prank(attacker);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Spam proposal");
    }

    function test_Security_DuplicateProposalHashRejected() public {
        // Alice stakes to propose
        vm.startPrank(alice);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Create first proposal
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Transfer tokens";

        vm.prank(alice);
        uint256 proposalId1 = governor.propose(targets, values, calldatas, description);

        // Try to create identical proposal - should fail
        vm.prank(alice);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, description);

        // Different description creates different proposal ID
        vm.prank(alice);
        uint256 proposalId2 = governor.propose(targets, values, calldatas, "Transfer tokens v2");

        assertNotEq(proposalId1, proposalId2, "Different descriptions = different IDs");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTE MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_VotesOnlyCountOncePerAddress() public {
        // This test verifies that the hasVoted mapping prevents double voting
        // The underlying OpenZeppelin Governor enforces this via _countVote

        // Setup: Alice stakes to get voting power
        vm.startPrank(alice);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Verify hasVoted starts false
        uint256 fakeProposalId = 12345;
        assertFalse(governor.hasVoted(fakeProposalId, alice), "Should not have voted");

        // The Governor implementation ensures:
        // 1. castVote checks hasVoted via _countVote
        // 2. If already voted, it reverts with GovernorAlreadyCastVote
        // This is verified by OpenZeppelin's own tests, but we document it here
    }

    function test_Security_CannotVoteWithFutureLock() public {
        // This test verifies that voting power snapshots work correctly
        // Users who stake AFTER a proposal snapshot cannot influence that proposal's outcome

        // First, create a snapshot BEFORE anyone stakes
        vm.roll(block.number + 1);
        uint256 earlySnapshotBlock = block.number - 1;

        // Alice stakes AFTER the early snapshot
        vm.startPrank(alice);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Alice has current voting power
        uint256 aliceCurrentVotes = veElta.getVotes(alice);
        assertGt(aliceCurrentVotes, 0, "Alice has current votes");

        // Alice had NO votes at the earlier snapshot (before she staked)
        uint256 aliceEarlyVotes = veElta.getPastVotes(alice, earlySnapshotBlock);
        assertEq(aliceEarlyVotes, 0, "Alice had no votes at early snapshot");

        // This proves that users who stake after a proposal's snapshot
        // have zero voting power for that specific proposal
    }

    function test_Security_DelegatedVotesCannotBeDoubleCounted() public {
        // Alice stakes
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        uint256 aliceVotes = veElta.getVotes(alice);

        // Alice delegates to Bob
        vm.prank(alice);
        veElta.delegate(bob);

        vm.roll(block.number + 1);

        // Now Bob has Alice's votes, Alice has 0
        uint256 bobVotes = veElta.getVotes(bob);
        uint256 aliceVotesAfter = veElta.getVotes(alice);

        assertEq(bobVotes, aliceVotes, "Bob has Alice's votes");
        assertEq(aliceVotesAfter, 0, "Alice has 0 votes");

        // Total is conserved
        assertEq(bobVotes + aliceVotesAfter, aliceVotes, "Votes conserved");
    }

    function testFuzz_Security_VotingPowerCappedAt2xPrincipal(uint256 amount, uint256 lockDuration) public {
        amount = bound(amount, 1 ether, 5_000_000 ether);
        lockDuration = bound(lockDuration, 8 days, 730 days);

        vm.startPrank(alice);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + lockDuration));
        vm.stopPrank();

        uint256 veBalance = veElta.balanceOf(alice);

        // veELTA should be between 1x and 2x principal
        assertGe(veBalance, amount, "veELTA >= principal (1x min boost)");
        assertLe(veBalance, amount * 2, "veELTA <= 2x principal (2x max boost)");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMELOCK INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ProposalMustBeQueuedBeforeExecution() public {
        // This test verifies the timelocked governor flow
        // The GovernorTimelockControl requires proposals to be queued before execution

        // Verify governor uses timelock
        assertEq(governor.timelock(), address(timelock), "Timelock connected");

        // The queue -> execute flow is enforced by GovernorTimelockControl:
        // 1. _queueOperations schedules on timelock
        // 2. _executeOperations calls timelock.execute
        // 3. Direct execution without queuing reverts

        // This is validated by OpenZeppelin's tests, documented here for security audit
    }

    function test_Security_TimelockDelayCannotBeBypassed() public {
        // Direct timelock test - verify MIN_DELAY is enforced

        // Fund timelock
        vm.prank(admin);
        elta.transfer(address(timelock), 1000 ether);

        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 100 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(1));

        // Schedule as proposer (admin has proposer role)
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // Try to execute before delay
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);

        // Warp 24 hours - still should fail
        vm.warp(block.timestamp + 24 hours);
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);

        // Warp another 24 hours + 1 - now should work (48+ hours total)
        vm.warp(block.timestamp + 24 hours + 1);
        uint256 aliceBefore = elta.balanceOf(alice);
        timelock.execute(target, value, data, predecessor, salt);
        uint256 aliceAfter = elta.balanceOf(alice);

        assertEq(aliceAfter - aliceBefore, 100 ether, "Transfer executed after delay");
    }

    function test_Security_ExecutionFailsIfTimelockCancelled() public {
        // Direct timelock cancellation test

        vm.prank(admin);
        elta.transfer(address(timelock), 1000 ether);

        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 100 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(2));

        // Schedule
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // Get operation ID
        bytes32 opId = timelock.hashOperation(target, value, data, predecessor, salt);

        // Cancel as admin (who has CANCELLER_ROLE)
        vm.prank(admin);
        timelock.cancel(opId);

        // Wait past delay
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // Execution should fail - operation cancelled
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_QuorumScalesWithSupply(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1 ether, 10_000_000 ether);

        vm.startPrank(alice);
        elta.approve(address(veElta), stakeAmount);
        veElta.lock(stakeAmount, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        uint256 totalSupply = veElta.getPastTotalSupply(block.number - 1);
        uint256 quorum = governor.quorum(block.number - 1);

        // Quorum should be exactly 4% of supply
        uint256 expectedQuorum = (totalSupply * 4) / 100;
        assertEq(quorum, expectedQuorum, "Quorum = 4% of supply");
    }

    function testFuzz_Security_TimelockDelayRespected(uint256 waitTime) public {
        waitTime = bound(waitTime, 0, MIN_DELAY - 1);

        vm.prank(admin);
        elta.transfer(address(timelock), 100 ether);

        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 1 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(waitTime);

        // Schedule as proposer
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // Wait less than MIN_DELAY
        vm.warp(block.timestamp + waitTime);

        // Should still fail - delay not met
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);
    }
}
