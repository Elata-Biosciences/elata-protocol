// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElataGovernor} from "../../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../../src/governance/ElataTimelock.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ELTA} from "elta/ELTA.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import "forge-std/Test.sol";

/**
 * @title GovernanceFullCycle Integration Test
 * @notice End-to-end governance flow tests
 * @dev Tests the complete governance lifecycle:
 *      1. Users lock ELTA in VeELTA
 *      2. Proposal creation
 *      3. Voting period
 *      4. Timelock queue and execution
 *      5. Parameter changes take effect
 */
contract GovernanceFullCycleTest is Test {
    ELTA public elta;
    VeELTA public veElta;
    ElataTimelock public timelock;
    ElataGovernor public governor;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");

    // Large token holders for governance participation
    address public whale1 = makeAddr("whale1");
    address public whale2 = makeAddr("whale2");
    address public whale3 = makeAddr("whale3");

    // Smaller holders
    address public holder1 = makeAddr("holder1");
    address public holder2 = makeAddr("holder2");

    uint256 public constant TOTAL_SUPPLY = 77_000_000 ether;
    uint256 public constant INITIAL_MINT = 50_000_000 ether;

    // Governance parameters
    uint256 public constant VOTING_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant TIMELOCK_DELAY = 48 hours;
    uint256 public constant PROPOSAL_THRESHOLD = 77_000 ether; // 0.1% of supply

    // A simple target contract for governance actions
    MockTarget public target;

    function setUp() public {
        // Start at a reasonable block/time
        vm.roll(1000);
        vm.warp(1000000);

        // Deploy ELTA token
        elta = new ELTA(treasury);

        // Deploy VeELTA
        veElta = new VeELTA(elta, admin);

        // Deploy timelock with governance as proposer/executor
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Anyone can propose through governor
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        timelock = new ElataTimelock(TIMELOCK_DELAY, proposers, executors, admin);

        // Deploy governor
        governor = new ElataGovernor(IVotes(address(veElta)), address(timelock));

        // Grant proposer role to governor
        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        vm.stopPrank();

        // Deploy target contract
        target = new MockTarget();

        // Transfer ownership of target to timelock (so governor can control it)
        target.transferOwnership(address(timelock));

        // Distribute tokens to whales
        vm.startPrank(treasury);
        elta.transfer(whale1, 5_000_000 ether); // 6.5% of supply
        elta.transfer(whale2, 3_000_000 ether); // 3.9% of supply
        elta.transfer(whale3, 2_000_000 ether); // 2.6% of supply
        elta.transfer(holder1, 500_000 ether);
        elta.transfer(holder2, 500_000 ether);
        vm.stopPrank();

        // Setup approvals for staking
        _setupApprovals(whale1);
        _setupApprovals(whale2);
        _setupApprovals(whale3);
        _setupApprovals(holder1);
        _setupApprovals(holder2);
    }

    function _setupApprovals(address user) internal {
        vm.prank(user);
        elta.approve(address(veElta), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FULL GOVERNANCE CYCLE TEST
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CompleteGovernanceCycle() public {
        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 1: Users stake ELTA to get voting power
        // ─────────────────────────────────────────────────────────────────────────

        // Whale1 stakes 5M ELTA (enough for proposal threshold)
        vm.prank(whale1);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));

        // Whale2 stakes 3M ELTA
        vm.prank(whale2);
        veElta.lock(3_000_000 ether, uint64(block.timestamp + 365 days));

        // Whale3 stakes 2M ELTA
        vm.prank(whale3);
        veElta.lock(2_000_000 ether, uint64(block.timestamp + 365 days));

        // Roll forward to create block history for voting
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Verify voting power
        uint256 whale1Votes = veElta.getVotes(whale1);
        uint256 whale2Votes = veElta.getVotes(whale2);
        uint256 whale3Votes = veElta.getVotes(whale3);

        assertGt(whale1Votes, PROPOSAL_THRESHOLD, "Whale1 should have enough votes to propose");
        console2.log("=== PHASE 1: Stakes Created ===");
        console2.log("Whale1 votes:", whale1Votes / 1e18);
        console2.log("Whale2 votes:", whale2Votes / 1e18);
        console2.log("Whale3 votes:", whale3Votes / 1e18);

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 2: Create a proposal
        // ─────────────────────────────────────────────────────────────────────────

        // Create proposal to update target contract value
        address[] memory targets = new address[](1);
        targets[0] = address(target);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setValue(uint256)", 42);

        string memory description = "Set target value to 42";

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(whale1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        console2.log("=== PHASE 2: Proposal Created ===");
        console2.log("Proposal ID:", proposalId);

        // Verify proposal state
        IGovernor.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Pending), "Should be Pending");

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 3: Voting period
        // ─────────────────────────────────────────────────────────────────────────

        // Wait for voting delay to pass (voting delay is in blocks)
        uint256 votingDelayBlocks = governor.votingDelay();
        vm.roll(block.number + votingDelayBlocks + 1);
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Active), "Should be Active");

        // Whales vote
        vm.prank(whale1);
        governor.castVote(proposalId, 1); // For

        vm.prank(whale2);
        governor.castVote(proposalId, 1); // For

        vm.prank(whale3);
        governor.castVote(proposalId, 0); // Against

        console2.log("=== PHASE 3: Votes Cast ===");
        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        console2.log("For:", forVotes / 1e18);
        console2.log("Against:", against / 1e18);
        console2.log("Abstain:", abstain / 1e18);

        // Wait for voting period to end (voting period is in blocks)
        uint256 votingPeriodBlocks = governor.votingPeriod();
        vm.roll(block.number + votingPeriodBlocks + 1);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Succeeded), "Should be Succeeded");

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 4: Queue and execute through timelock
        // ─────────────────────────────────────────────────────────────────────────

        // Queue the proposal
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Queued), "Should be Queued");

        console2.log("=== PHASE 4: Proposal Queued ===");

        // Wait for timelock delay
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Execute the proposal
        governor.execute(targets, values, calldatas, descriptionHash);

        state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Executed), "Should be Executed");

        // ─────────────────────────────────────────────────────────────────────────
        // PHASE 5: Verify changes took effect
        // ─────────────────────────────────────────────────────────────────────────

        assertEq(target.value(), 42, "Target value should be updated");

        console2.log("=== PHASE 5: Execution Complete ===");
        console2.log("Target value:", target.value());
        console2.log("");
        console2.log("=== FULL GOVERNANCE CYCLE COMPLETE ===");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL GOVERNANCE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProposalFailsWithoutQuorum() public {
        // Stake enough total supply to create reasonable quorum requirement
        // We need lots of stakers but only a few voting
        vm.prank(whale1);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(whale2);
        veElta.lock(3_000_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(whale3);
        veElta.lock(2_000_000 ether, uint64(block.timestamp + 365 days));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Total staked: 10M. Quorum is 4% = 400k votes needed
        // If only holder1 votes with 0 votes, quorum won't be met

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setValue(uint256)", 100);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(whale1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");

        // Move to voting
        uint256 votingDelayBlocks = governor.votingDelay();
        vm.roll(block.number + votingDelayBlocks + 1);
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        // Nobody votes - proposal will fail due to lack of quorum
        // (We can't vote with 0 stake, so we just let the proposal expire)

        // End voting period
        uint256 votingPeriodBlocks = governor.votingPeriod();
        vm.roll(block.number + votingPeriodBlocks + 1);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Should be defeated due to lack of quorum (no votes cast)
        IGovernor.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Defeated), "Should be Defeated without quorum");
    }

    function test_ProposalDefeatedByVotes() public {
        // All whales stake
        vm.prank(whale1);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(whale2);
        veElta.lock(3_000_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(whale3);
        veElta.lock(2_000_000 ether, uint64(block.timestamp + 365 days));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setValue(uint256)", 999);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(whale1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Controversial proposal");

        // Move to voting
        uint256 votingDelayBlocks = governor.votingDelay();
        vm.roll(block.number + votingDelayBlocks + 1);
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        // Majority votes against
        vm.prank(whale1);
        governor.castVote(proposalId, 1); // For (5M)

        vm.prank(whale2);
        governor.castVote(proposalId, 0); // Against (3M)

        vm.prank(whale3);
        governor.castVote(proposalId, 0); // Against (2M)

        // End voting period
        uint256 votingPeriodBlocks = governor.votingPeriod();
        vm.roll(block.number + votingPeriodBlocks + 1);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Should be defeated (5M for < 5M against)
        IGovernor.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Defeated), "Should be Defeated by votes");
    }

    function test_VotingPowerDelegation() public {
        // Whale1 stakes
        vm.prank(whale1);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));

        vm.roll(block.number + 1);

        uint256 whale1VotesBefore = veElta.getVotes(whale1);
        uint256 holder1VotesBefore = veElta.getVotes(holder1);

        assertGt(whale1VotesBefore, 0, "Whale1 should have votes");
        assertEq(holder1VotesBefore, 0, "Holder1 should have no votes");

        // Whale1 delegates to holder1
        vm.prank(whale1);
        veElta.delegate(holder1);

        vm.roll(block.number + 1);

        uint256 whale1VotesAfter = veElta.getVotes(whale1);
        uint256 holder1VotesAfter = veElta.getVotes(holder1);

        assertEq(whale1VotesAfter, 0, "Whale1 should have no votes after delegation");
        assertGt(holder1VotesAfter, 0, "Holder1 should have received delegated votes");
    }

    function test_CannotVoteTwice() public {
        vm.prank(whale1);
        veElta.lock(5_000_000 ether, uint64(block.timestamp + 365 days));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setValue(uint256)", 1);

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        vm.prank(whale1);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");

        // Move to voting
        uint256 votingDelayBlocks = governor.votingDelay();
        vm.roll(block.number + votingDelayBlocks + 1);
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        // First vote
        vm.prank(whale1);
        governor.castVote(proposalId, 1);

        // Second vote should fail
        vm.expectRevert();
        vm.prank(whale1);
        governor.castVote(proposalId, 0);
    }

    function test_GovernanceThresholds() public view {
        // Verify governance parameters are set correctly
        // Governor settings use time-based values
        assertEq(governor.votingDelay(), VOTING_DELAY, "Voting delay wrong");
        assertEq(governor.votingPeriod(), VOTING_PERIOD, "Voting period wrong");
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD, "Proposal threshold wrong");

        // Quorum numerator should be 4 (4%)
        assertEq(governor.quorumNumerator(), 4, "Quorum numerator wrong");
    }
}

// Simple target contract for governance actions
contract MockTarget {
    uint256 public value;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
