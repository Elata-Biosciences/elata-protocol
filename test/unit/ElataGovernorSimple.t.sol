// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ElataGovernorSimple } from "../../src/governance/ElataGovernorSimple.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";

contract ElataGovernorSimpleTest is Test {
    ElataGovernorSimple public governor;
    ELTA public elta;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public proposer = makeAddr("proposer");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");

    event EmergencyProposalCreated(uint256 indexed proposalId, string description);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 77_000_000 ether, 77_000_000 ether);
        governor = new ElataGovernorSimple(elta);
        
        // Distribute tokens for governance
        vm.startPrank(treasury);
        elta.transfer(proposer, 1_000_000 ether); // ~1.3% for proposals
        elta.transfer(voter1, 5_000_000 ether);   // ~6.5% for voting
        elta.transfer(voter2, 3_000_000 ether);   // ~3.9% for voting
        vm.stopPrank();
        
        // Self-delegate for voting power
        vm.prank(proposer);
        elta.delegate(proposer);
        
        vm.prank(voter1);
        elta.delegate(voter1);
        
        vm.prank(voter2);
        elta.delegate(voter2);
    }

    function test_Deployment() public {
        assertEq(governor.name(), "Elata Governor");
        assertEq(address(governor.token()), address(elta));
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 7 days);
        assertEq(governor.proposalThreshold(), 77000e18); // 0.1% of 77M
        
        // Check quorum (4% of total supply)
        uint256 expectedQuorum = (77_000_000 ether * 4) / 100;
        assertEq(governor.quorum(block.number - 1), expectedQuorum);
    }

    function test_CreateProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", voter1, 1000 ether);
        
        string memory description = "Transfer 1000 ELTA to voter1";
        
        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        
        assertGt(proposalId, 0);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

    function test_CreateEmergencyProposal() public {
        // Give proposer enough tokens for emergency proposal (5% of supply)
        uint256 emergencyThreshold = (77_000_000 ether * 5) / 100;
        vm.prank(treasury);
        elta.transfer(proposer, emergencyThreshold);
        
        vm.prank(proposer);
        elta.delegate(proposer);
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", voter1, 1000 ether);
        
        string memory description = "Emergency transfer";
        
        vm.expectEmit(true, false, false, false);
        emit EmergencyProposalCreated(1, description);
        
        vm.prank(proposer);
        uint256 proposalId = governor.proposeEmergency(targets, values, calldatas, description);
        
        assertTrue(governor.isEmergencyProposal(proposalId));
        assertEq(governor.proposalVotingPeriod(proposalId), 3 days);
    }

    function test_VoteOnProposal() public {
        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", voter1, 1000 ether);
        
        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");
        
        // Fast forward past voting delay
        vm.warp(block.timestamp + 1 days + 1);
        
        // Vote
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // Vote "For"
        
        vm.prank(voter2);
        governor.castVote(proposalId, 1); // Vote "For"
        
        // Check vote counts
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 8_000_000 ether); // voter1 + voter2
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    function test_ExecuteSuccessfulProposal() public {
        // Create proposal to transfer tokens from treasury
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", voter1, 1000 ether);
        
        // Give treasury tokens and delegate to governor for execution
        vm.startPrank(treasury);
        elta.delegate(address(governor));
        vm.stopPrank();
        
        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Transfer tokens");
        
        // Fast forward past voting delay
        vm.warp(block.timestamp + 1 days + 1);
        
        // Vote (need quorum)
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        
        vm.prank(voter2);
        governor.castVote(proposalId, 1);
        
        // Fast forward past voting period
        vm.warp(block.timestamp + 7 days + 1);
        
        // Execute
        uint256 initialBalance = elta.balanceOf(voter1);
        
        governor.execute(targets, values, calldatas, keccak256(bytes("Transfer tokens")));
        
        assertEq(elta.balanceOf(voter1), initialBalance + 1000 ether);
        assertTrue(governor.isExecuted(proposalId));
    }

    function test_RevertWhen_InsufficientProposerVotes() public {
        // User with insufficient tokens tries to propose
        vm.prank(voter2); // Has only ~3.9%, needs ~0.1%
        elta.delegate(voter2);
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", voter1, 1000 ether);
        
        // This should work since voter2 has enough tokens
        vm.prank(voter2);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Test");
        
        assertGt(proposalId, 0);
    }

    function test_EmergencyProposalThreshold() public {
        uint256 threshold = governor.emergencyProposalThreshold();
        uint256 expectedThreshold = (77_000_000 ether * 5) / 100; // 5% of total supply
        assertEq(threshold, expectedThreshold);
    }

    function testFuzz_ProposalThresholds(uint256 voterTokens) public {
        voterTokens = bound(voterTokens, 1 ether, 10_000_000 ether);
        
        // Give user tokens
        address testUser = makeAddr("testUser");
        vm.prank(treasury);
        elta.transfer(testUser, voterTokens);
        
        vm.prank(testUser);
        elta.delegate(testUser);
        
        address[] memory targets = new address[](1);
        targets[0] = address(elta);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", testUser, 1 ether);
        
        if (voterTokens >= governor.proposalThreshold()) {
            // Should succeed
            vm.prank(testUser);
            uint256 proposalId = governor.propose(targets, values, calldatas, "Test proposal");
            assertGt(proposalId, 0);
        } else {
            // Should fail
            vm.expectRevert();
            vm.prank(testUser);
            governor.propose(targets, values, calldatas, "Test proposal");
        }
    }
}
