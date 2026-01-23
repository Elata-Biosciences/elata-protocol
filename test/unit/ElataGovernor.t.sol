// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ElataGovernor} from "../../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../../src/governance/ElataTimelock.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title ElataGovernor Unit Tests
 * @notice Tests for veELTA-based governance
 * @dev Verifies voting power derives from veELTA locks, not ELTA balance
 */
contract ElataGovernorTest is Test {
    ELTA public elta;
    VeELTA public veELTA;
    ElataGovernor public governor;
    ElataTimelock public timelock;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant TOTAL_SUPPLY = 77_000_000 ether;
    uint256 public constant INITIAL_MINT = 10_000_000 ether;

    function setUp() public {
        // Deploy ELTA token
        elta = new ELTA("ELTA", "ELTA", admin, treasury, INITIAL_MINT, TOTAL_SUPPLY);

        // Deploy veELTA staking
        veELTA = new VeELTA(elta, admin);

        // Deploy timelock with proposers and executors
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Anyone can propose through governor
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        timelock = new ElataTimelock(48 hours, proposers, executors, admin);

        // Deploy governor using veELTA for voting
        governor = new ElataGovernor(IVotes(address(veELTA)), address(timelock));

        // Distribute tokens for testing
        vm.startPrank(treasury);
        elta.transfer(alice, 2_000_000 ether);
        elta.transfer(bob, 1_500_000 ether);
        elta.transfer(charlie, 500_000 ether);
        vm.stopPrank();
    }

    // =========== Deployment Tests ===========

    function test_Deployment() public view {
        assertEq(address(governor.token()), address(veELTA));
        assertEq(governor.name(), "Elata Governor");
    }

    function test_GovernorUsesVeELTANotELTA() public {
        // Verify governor's token is veELTA
        assertEq(address(governor.token()), address(veELTA));
        assertNotEq(address(governor.token()), address(elta));
    }

    // =========== Voting Power Tests ===========

    function test_NoVotingPowerWithoutStaking() public {
        // Alice has ELTA but hasn't staked
        assertGt(elta.balanceOf(alice), 0);
        assertEq(veELTA.balanceOf(alice), 0);

        // Alice has no voting power in governor
        vm.roll(block.number + 1);
        assertEq(governor.getVotes(alice, block.number - 1), 0);
    }

    function test_VotingPowerFromVeELTALock() public {
        // Alice stakes ELTA to get veELTA
        vm.startPrank(alice);
        elta.approve(address(veELTA), 1_000_000 ether);
        veELTA.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Move forward for checkpoint
        vm.roll(block.number + 1);

        // Alice now has voting power
        uint256 votingPower = governor.getVotes(alice, block.number - 1);
        assertGt(votingPower, 0);

        // Voting power equals veELTA balance (with boost)
        assertEq(votingPower, veELTA.getPastVotes(alice, block.number - 1));
    }

    function test_VotingPowerIncreasesWithLongerLock() public {
        // Alice locks for 1 year
        vm.startPrank(alice);
        elta.approve(address(veELTA), 1_000_000 ether);
        veELTA.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);
        uint256 alicePower = governor.getVotes(alice, block.number - 1);

        // Bob locks same amount for 2 years (max duration)
        vm.startPrank(bob);
        elta.approve(address(veELTA), 1_000_000 ether);
        veELTA.lock(1_000_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        vm.roll(block.number + 1);
        uint256 bobPower = governor.getVotes(bob, block.number - 1);

        // Bob should have more voting power due to longer lock
        assertGt(bobPower, alicePower);
    }

    function test_VotingPowerLostAfterUnlock() public {
        // Alice locks ELTA (must be > MIN_LOCK from current timestamp)
        uint64 unlockTime = uint64(block.timestamp + 8 days); // > MIN_LOCK (7 days)
        vm.startPrank(alice);
        elta.approve(address(veELTA), 1_000_000 ether);
        veELTA.lock(1_000_000 ether, unlockTime);
        vm.stopPrank();

        vm.roll(block.number + 1);
        uint256 powerBefore = governor.getVotes(alice, block.number - 1);
        assertGt(powerBefore, 0);

        // Time passes, Alice unlocks
        vm.warp(unlockTime + 1);
        vm.roll(block.number + 1);

        vm.prank(alice);
        veELTA.unlock();

        vm.roll(block.number + 1);
        uint256 powerAfter = governor.getVotes(alice, block.number - 1);
        assertEq(powerAfter, 0);
    }

    // =========== Governance Parameters Tests ===========

    function test_GovernanceParameters() public view {
        // Verify governance parameters
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 7 days);
        assertEq(governor.proposalThreshold(), 77000e18); // 0.1% of 77M
    }

    function test_QuorumCalculation() public {
        // Stake to create supply
        vm.startPrank(alice);
        elta.approve(address(veELTA), 1_000_000 ether);
        veELTA.lock(1_000_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Quorum should be 4% of veELTA total supply
        uint256 quorum = governor.quorum(block.number - 1);
        uint256 expectedQuorum = (veELTA.getPastTotalSupply(block.number - 1) * 4) / 100;
        assertEq(quorum, expectedQuorum);
    }

    // =========== Proposal Threshold Tests ===========

    function test_CanCreateProposalWithEnoughVeELTA() public {
        // Alice needs enough veELTA to meet proposal threshold (77K tokens)
        // Since there's boost, she needs to lock enough to get 77K+ veELTA
        vm.startPrank(alice);
        elta.approve(address(veELTA), 100_000 ether);
        veELTA.lock(100_000 ether, uint64(block.timestamp + 730 days)); // Max lock for max boost
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Verify Alice has enough voting power
        uint256 alicePower = governor.getVotes(alice, block.number - 1);
        assertGt(alicePower, governor.proposalThreshold());

        // Create a simple proposal
        address[] memory targets = new address[](1);
        targets[0] = address(veELTA);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = ""; // Empty calldata

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");
        assertGt(proposalId, 0);
    }

    function test_CannotCreateProposalWithoutEnoughVeELTA() public {
        // Charlie has small amount of ELTA
        vm.startPrank(charlie);
        elta.approve(address(veELTA), 10_000 ether);
        veELTA.lock(10_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Verify Charlie doesn't have enough voting power
        uint256 charliePower = governor.getVotes(charlie, block.number - 1);
        assertLt(charliePower, governor.proposalThreshold());

        // Try to create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(veELTA);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        vm.prank(charlie);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Test proposal");
    }

    // =========== Emergency Proposal Tests ===========

    function test_EmergencyProposalHigherThreshold() public {
        // Need veELTA staked first
        vm.startPrank(alice);
        elta.approve(address(veELTA), 2_000_000 ether);
        veELTA.lock(2_000_000 ether, uint64(block.timestamp + 730 days));
        vm.stopPrank();

        // Roll forward so snapshot is available
        vm.roll(block.number + 1);

        // Emergency proposal requires 5% of supply
        uint256 emergencyThreshold = governor.emergencyProposalThreshold();

        // Emergency threshold should be 5% of veELTA total supply
        uint256 expectedThreshold = (veELTA.getPastTotalSupply(block.number - 1) * 500) / 10000;
        assertGt(expectedThreshold, 0); // Verify supply is tracked
        assertEq(emergencyThreshold, expectedThreshold);
    }

    // =========== Timelock Integration Tests ===========

    function test_TimelockAddressSet() public view {
        assertEq(governor.timelock(), address(timelock));
    }

    // =========== Fuzz Tests ===========

    function testFuzz_VotingPowerScalesWithLockAmount(uint256 lockAmount) public {
        lockAmount = bound(lockAmount, 1 ether, 1_000_000 ether);

        vm.startPrank(alice);
        elta.approve(address(veELTA), lockAmount);
        veELTA.lock(lockAmount, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.roll(block.number + 1);

        uint256 votingPower = governor.getVotes(alice, block.number - 1);

        // Voting power should be at least the locked amount (1x boost minimum)
        assertGe(votingPower, lockAmount);
        // And at most 2x the locked amount (2x boost maximum)
        assertLe(votingPower, lockAmount * 2);
    }
}
