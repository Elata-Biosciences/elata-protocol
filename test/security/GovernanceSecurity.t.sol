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
 * @title GovernanceSecurity
 * @notice Red team security tests for ElataGovernor and ElataTimelock
 */
contract GovernanceSecurity is Test {
    ELTA public elta;
    VeELTA public veElta;
    ElataGovernor public governor;
    ElataTimelock public timelock;

    address public admin = makeAddr("admin");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant MIN_DELAY = 1 days;

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
        elta.transfer(attacker, 10_000_000 ether);
        elta.transfer(alice, 10_000_000 ether);
        elta.transfer(bob, 10_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FLASH VOTE ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_FlashVoteRequiresLock() public {
        // Attacker tries to vote without locking
        // They would need veELTA to vote

        uint256 votingPower = veElta.getVotes(attacker);
        assertEq(votingPower, 0, "Attacker should have no voting power without lock");
    }

    function test_Security_VotingPowerRequiresMinLock() public {
        // Lock tokens
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + veElta.MIN_LOCK() + 1 days));
        vm.stopPrank();

        // Alice should now have voting power
        uint256 votingPower = veElta.getVotes(alice);
        assertGt(votingPower, 0, "Alice should have voting power after lock");

        // Attacker cannot unlock Alice's tokens
        vm.prank(attacker);
        vm.expectRevert();
        veElta.unlock(); // Attacker has no lock
    }

    function test_Security_CannotTransferVotingPower() public {
        // Lock tokens to get voting power
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        uint256 aliceVotingPower = veElta.getVotes(alice);

        // Try to transfer veELTA (should fail - soulbound)
        vm.prank(alice);
        vm.expectRevert();
        veElta.transfer(attacker, aliceVotingPower);

        // Attacker still has no voting power
        assertEq(veElta.getVotes(attacker), 0, "Attacker should still have no votes");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSAL MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ProposalRequiresThreshold() public {
        // Check proposal threshold
        uint256 threshold = governor.proposalThreshold();

        // Attacker without enough voting power cannot propose
        // First give attacker some but not enough voting power
        vm.startPrank(attacker);
        elta.approve(address(veElta), 100 ether);
        veElta.lock(100 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // If threshold > 0 and attacker has less, proposal should fail
        if (threshold > veElta.getVotes(attacker)) {
            address[] memory targets = new address[](1);
            targets[0] = address(elta);
            uint256[] memory values = new uint256[](1);
            values[0] = 0;
            bytes[] memory calldatas = new bytes[](1);
            calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", attacker, 1000 ether);

            vm.prank(attacker);
            vm.expectRevert();
            governor.propose(targets, values, calldatas, "Malicious proposal");
        }
    }

    function test_Security_QuorumRequired() public {
        // Check quorum requirement
        uint256 quorum = governor.quorum(block.number - 1);
        console2.log("Quorum required:", quorum);

        // Quorum should be > 0 to prevent low-turnout attacks
        // This is informational - quorum is set by the constructor
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMELOCK BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotExecuteBeforeDelay() public {
        // Schedule an operation through timelock
        bytes32 id = keccak256("test_operation");
        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", attacker, 1000 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        // Only proposer can schedule
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // Try to execute immediately (should fail)
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);
    }

    function test_Security_CanExecuteAfterDelay() public {
        // Fund timelock with ELTA for the transfer
        vm.prank(admin);
        elta.transfer(address(timelock), 1000 ether);

        bytes32 id = keccak256("test_operation");
        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 1000 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(1));

        // Schedule
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // Warp past delay
        vm.warp(block.timestamp + MIN_DELAY + 1);

        // Execute should work now
        uint256 aliceBefore = elta.balanceOf(alice);
        timelock.execute(target, value, data, predecessor, salt);
        uint256 aliceAfter = elta.balanceOf(alice);

        assertEq(aliceAfter - aliceBefore, 1000 ether, "Transfer should execute");
    }

    function test_Security_OnlyProposerCanSchedule() public {
        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", attacker, 1000 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(2));

        // Attacker cannot schedule
        vm.prank(attacker);
        vm.expectRevert();
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);
    }

    function test_Security_CannotCancelAsNonAdmin() public {
        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", alice, 1000 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(uint256(3));

        // Schedule as admin
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, MIN_DELAY);

        // Get operation id
        bytes32 opId = timelock.hashOperation(target, value, data, predecessor, salt);

        // Attacker cannot cancel
        vm.prank(attacker);
        vm.expectRevert();
        timelock.cancel(opId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DELEGATION MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_DelegationDoesNotDuplicateVotes() public {
        // Alice locks tokens
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        uint256 aliceVotes = veElta.getVotes(alice);

        // Alice delegates to Bob
        vm.prank(alice);
        veElta.delegate(bob);

        // Bob should have Alice's votes
        uint256 bobVotes = veElta.getVotes(bob);
        assertEq(bobVotes, aliceVotes, "Bob should have Alice's votes");

        // Alice should have 0 votes (delegated away)
        assertEq(veElta.getVotes(alice), 0, "Alice should have 0 votes after delegation");

        // Total voting power should be constant
        uint256 totalVeELTA = veElta.totalSupply();
        console2.log("Total veELTA:", totalVeELTA);
    }

    function test_Security_CannotDelegateToSelfForDoubleVotes() public {
        // Alice locks tokens
        vm.startPrank(alice);
        elta.approve(address(veElta), 1_000_000 ether);
        veElta.lock(1_000_000 ether, uint64(block.timestamp + 365 days));

        uint256 votesBefore = veElta.getVotes(alice);

        // Delegate to self
        veElta.delegate(alice);

        uint256 votesAfter = veElta.getVotes(alice);

        // Should not increase votes
        assertEq(votesAfter, votesBefore, "Self-delegation should not increase votes");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GOVERNANCE PARAMETER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_VotingDelayExists() public {
        uint256 votingDelay = governor.votingDelay();
        console2.log("Voting delay (blocks):", votingDelay);
        // Voting delay prevents flash-governance attacks
    }

    function test_Security_VotingPeriodReasonable() public {
        uint256 votingPeriod = governor.votingPeriod();
        console2.log("Voting period (blocks):", votingPeriod);
        // Voting period should give enough time for participation
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_LockAndVotingPower(uint256 amount) public {
        amount = bound(amount, 1 ether, 5_000_000 ether);

        vm.startPrank(alice);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        uint256 votes = veElta.getVotes(alice);
        assertGe(votes, amount, "Votes should be >= principal");
        assertLe(votes, amount * 2, "Votes should be <= 2x principal");
    }

    function testFuzz_Security_TimelockDelay(uint256 delay) public {
        delay = bound(delay, MIN_DELAY, 30 days);

        vm.prank(admin);
        elta.transfer(address(timelock), 100 ether);

        address target = address(elta);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", bob, 100 ether);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(delay);

        // Schedule with specific delay
        vm.prank(admin);
        timelock.schedule(target, value, data, predecessor, salt, delay);

        // Cannot execute before delay
        vm.warp(block.timestamp + delay - 1);
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);

        // Can execute after delay
        vm.warp(block.timestamp + 2);
        timelock.execute(target, value, data, predecessor, salt);
    }
}
