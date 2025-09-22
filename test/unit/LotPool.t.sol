// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { LotPool } from "../../src/governance/LotPool.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

contract LotPoolTest is Test {
    LotPool public lotPool;
    ElataXP public xp;
    ELTA public elta;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public recipient1 = makeAddr("recipient1");
    address public recipient2 = makeAddr("recipient2");

    bytes32 public constant OPTION_1 = keccak256("OPTION_1");
    bytes32 public constant OPTION_2 = keccak256("OPTION_2");

    event RoundStarted(uint256 indexed roundId, uint256 snapshotBlock, uint64 start, uint64 end);
    event OptionAdded(uint256 indexed roundId, bytes32 option, address recipient);
    event Voted(uint256 indexed roundId, address indexed voter, bytes32 option, uint256 weight);
    event Finalized(uint256 indexed roundId, bytes32 winner, uint256 amount, address recipient);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        xp = new ElataXP(admin);
        lotPool = new LotPool(elta, xp, admin);

        // Give users some XP
        vm.startPrank(admin);
        xp.award(user1, 1000 ether);
        xp.award(user2, 500 ether);
        xp.award(user3, 200 ether);
        vm.stopPrank();

        // Fund the lot pool
        vm.startPrank(treasury);
        elta.approve(address(lotPool), 100000 ether);
        lotPool.fund(100000 ether);
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(lotPool.ELTA()), address(elta));
        assertEq(address(lotPool.XP()), address(xp));
        assertTrue(lotPool.hasRole(lotPool.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(lotPool.hasRole(lotPool.MANAGER_ROLE(), admin));
        assertEq(lotPool.currentRoundId(), 0);
    }

    function test_RevertWhen_DeploymentZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new LotPool(ELTA(address(0)), xp, admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new LotPool(elta, ElataXP(address(0)), admin);

        vm.expectRevert(Errors.ZeroAddress.selector);
        new LotPool(elta, xp, address(0));
    }

    function test_Fund() public {
        uint256 fundAmount = 10000 ether;
        uint256 initialBalance = elta.balanceOf(address(lotPool));

        vm.startPrank(treasury);
        elta.approve(address(lotPool), fundAmount);
        lotPool.fund(fundAmount);
        vm.stopPrank();

        assertEq(elta.balanceOf(address(lotPool)), initialBalance + fundAmount);
    }

    function test_RevertWhen_FundZeroAmount() public {
        vm.expectRevert(Errors.InvalidAmount.selector);
        vm.prank(treasury);
        lotPool.fund(0);
    }

    function test_StartRound() public {
        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_2;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint64 duration = 7 days;

        vm.expectEmit(true, false, false, true);
        emit RoundStarted(
            1,
            block.number > 0 ? block.number - 1 : 0,
            uint64(block.timestamp),
            uint64(block.timestamp + duration)
        );

        vm.prank(admin);
        (uint256 roundId, uint256 snapshotBlock) = lotPool.startRound(options, recipients, duration);

        assertEq(roundId, 1);
        assertEq(snapshotBlock, block.number > 0 ? block.number - 1 : 0);
        assertEq(lotPool.currentRoundId(), 1);

        (
            uint256 returnedSnapshotBlock,
            uint64 start,
            uint64 end,
            bool finalized,
            bytes32[] memory returnedOptions
        ) = lotPool.getRound(roundId);
        assertEq(returnedSnapshotBlock, snapshotBlock);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + duration);
        assertFalse(finalized);
        assertEq(returnedOptions.length, 2);
        assertEq(returnedOptions[0], OPTION_1);
        assertEq(returnedOptions[1], OPTION_2);
    }

    function test_RevertWhen_StartRoundEmptyOptions() public {
        bytes32[] memory options = new bytes32[](0);
        address[] memory recipients = new address[](0);

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(admin);
        lotPool.startRound(options, recipients, 7 days);
    }

    function test_RevertWhen_StartRoundMismatchedArrays() public {
        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_2;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.expectRevert(Errors.ArrayLengthMismatch.selector);
        vm.prank(admin);
        lotPool.startRound(options, recipients, 7 days);
    }

    function test_RevertWhen_StartRoundZeroRecipient() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(admin);
        lotPool.startRound(options, recipients, 7 days);
    }

    function test_RevertWhen_StartRoundDuplicateOptions() public {
        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_1; // duplicate

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        vm.expectRevert(Errors.DuplicateOption.selector);
        vm.prank(admin);
        lotPool.startRound(options, recipients, 7 days);
    }

    function test_Vote() public {
        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        // Start a round
        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_2;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // Vote with user1
        uint256 voteWeight = 500 ether;

        vm.expectEmit(true, true, false, true);
        emit Voted(roundId, user1, OPTION_1, voteWeight);

        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, voteWeight);

        assertEq(lotPool.votesFor(roundId, OPTION_1), voteWeight);
    }

    function test_RevertWhen_VoteNotStarted() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // Rewind time before round start
        vm.warp(block.timestamp - 1);

        vm.expectRevert(Errors.VotingNotStarted.selector);
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, 100 ether);
    }

    function test_RevertWhen_VotingClosed() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // Fast forward past round end
        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(Errors.VotingClosed.selector);
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, 100 ether);
    }

    function test_RevertWhen_VoteInvalidOption() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        vm.expectRevert(Errors.DuplicateOption.selector); // reused error
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_2, 100 ether); // OPTION_2 not in round
    }

    function test_RevertWhen_VoteInsufficientXP() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // Try to vote with more XP than user has
        vm.expectRevert(Errors.InsufficientXP.selector);
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, 2000 ether); // user1 only has 1000 XP
    }

    function test_VoteMultipleOptions() public {
        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_2;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // User1 splits their XP between options
        vm.startPrank(user1);
        lotPool.vote(roundId, OPTION_1, 600 ether);
        lotPool.vote(roundId, OPTION_2, 400 ether);
        vm.stopPrank();

        assertEq(lotPool.votesFor(roundId, OPTION_1), 600 ether);
        assertEq(lotPool.votesFor(roundId, OPTION_2), 400 ether);
    }

    function test_RevertWhen_VoteExceedsXP() public {
        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_2;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // User1 votes with 600 XP first
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, 600 ether);

        // Try to vote with remaining 500 XP (would exceed 1000 total)
        vm.expectRevert(Errors.InsufficientXP.selector);
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_2, 500 ether);
    }

    function test_Finalize() public {
        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        bytes32[] memory options = new bytes32[](2);
        options[0] = OPTION_1;
        options[1] = OPTION_2;

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // Users vote
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, 800 ether);

        vm.prank(user2);
        lotPool.vote(roundId, OPTION_2, 500 ether);

        // Fast forward past round end
        vm.warp(block.timestamp + 8 days);

        uint256 payoutAmount = 5000 ether;
        uint256 initialBalance = elta.balanceOf(recipient1);

        vm.expectEmit(true, false, false, true);
        emit Finalized(roundId, OPTION_1, payoutAmount, recipient1);

        vm.prank(admin);
        lotPool.finalize(roundId, OPTION_1, payoutAmount);

        assertEq(elta.balanceOf(recipient1), initialBalance + payoutAmount);

        // Check round is marked as finalized
        (,,, bool finalized,) = lotPool.getRound(roundId);
        assertTrue(finalized);
    }

    function test_RevertWhen_FinalizeVotingNotEnded() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        vm.expectRevert(Errors.VotingClosed.selector);
        vm.prank(admin);
        lotPool.finalize(roundId, OPTION_1, 1000 ether);
    }

    function test_RevertWhen_FinalizeInvalidWinner() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(Errors.DuplicateOption.selector);
        vm.prank(admin);
        lotPool.finalize(roundId, OPTION_2, 1000 ether); // OPTION_2 not in round
    }

    function test_FinalizeZeroAmount() public {
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        vm.warp(block.timestamp + 8 days);

        uint256 initialBalance = elta.balanceOf(recipient1);

        vm.prank(admin);
        lotPool.finalize(roundId, OPTION_1, 0);

        assertEq(elta.balanceOf(recipient1), initialBalance); // No change
    }

    function test_MultipleRounds() public {
        // Round 1
        bytes32[] memory options1 = new bytes32[](1);
        options1[0] = OPTION_1;

        address[] memory recipients1 = new address[](1);
        recipients1[0] = recipient1;

        vm.prank(admin);
        (uint256 round1Id,) = lotPool.startRound(options1, recipients1, 7 days);

        vm.warp(block.timestamp + 8 days);

        vm.prank(admin);
        lotPool.finalize(round1Id, OPTION_1, 1000 ether);

        // Round 2
        bytes32[] memory options2 = new bytes32[](1);
        options2[0] = OPTION_2;

        address[] memory recipients2 = new address[](1);
        recipients2[0] = recipient2;

        vm.prank(admin);
        (uint256 round2Id,) = lotPool.startRound(options2, recipients2, 7 days);

        assertEq(round1Id, 1);
        assertEq(round2Id, 2);
        assertEq(lotPool.currentRoundId(), 2);
    }

    function testFuzz_Vote(uint256 xpAmount, uint256 voteWeight) public {
        xpAmount = bound(xpAmount, 1 ether, 10000 ether);
        voteWeight = bound(voteWeight, 1, xpAmount);

        // Give user XP
        vm.prank(admin);
        xp.award(user1, xpAmount);

        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        // Start round
        bytes32[] memory options = new bytes32[](1);
        options[0] = OPTION_1;

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        vm.prank(admin);
        (uint256 roundId,) = lotPool.startRound(options, recipients, 7 days);

        // Vote
        vm.prank(user1);
        lotPool.vote(roundId, OPTION_1, voteWeight);

        assertEq(lotPool.votesFor(roundId, OPTION_1), voteWeight);
    }
}
