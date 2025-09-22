// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ElataXP } from "../../src/xp/ElataXP.sol";
import { LotPool } from "../../src/governance/LotPool.sol";

contract ProtocolIntegrationTest is Test {
    ELTA public elta;
    VeELTA public veELTA;
    ElataXP public xp;
    LotPool public lotPool;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public researcher1 = makeAddr("researcher1");
    address public researcher2 = makeAddr("researcher2");

    uint256 public constant INITIAL_MINT = 10_000_000 ether;
    uint256 public constant MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy all contracts
        elta = new ELTA("ELTA", "ELTA", admin, treasury, INITIAL_MINT, MAX_SUPPLY);
        veELTA = new VeELTA(elta, admin);
        xp = new ElataXP(admin);
        lotPool = new LotPool(elta, xp, admin);

        // Distribute ELTA to users
        vm.startPrank(treasury);
        elta.transfer(alice, 100000 ether);
        elta.transfer(bob, 50000 ether);
        elta.transfer(charlie, 25000 ether);
        vm.stopPrank();
    }

    function test_FullProtocolFlow() public {
        // 1. Users stake ELTA for voting power
        _stakeELTA();

        // 2. Users earn XP through various activities
        _earnXP();

        // 3. Fund the lot pool for research grants
        _fundLotPool();

        // 4. Start a funding round
        uint256 roundId = _startFundingRound();

        // 5. Users vote with their XP
        _voteInRound(roundId);

        // 6. Finalize round and distribute funds
        _finalizeRound(roundId);

        // 7. Test withdrawal after lock expires
        _testWithdrawal();
    }

    function _stakeELTA() internal {
        // Alice stakes for 2 years (maximum lock)
        vm.startPrank(alice);
        elta.approve(address(veELTA), 50000 ether);
        veELTA.createLock(50000 ether, veELTA.MAX_LOCK());
        vm.stopPrank();

        // Bob stakes for 1 year
        vm.startPrank(bob);
        elta.approve(address(veELTA), 30000 ether);
        veELTA.createLock(30000 ether, 52 weeks);
        vm.stopPrank();

        // Charlie stakes for 6 months
        vm.startPrank(charlie);
        elta.approve(address(veELTA), 15000 ether);
        veELTA.createLock(15000 ether, 26 weeks);
        vm.stopPrank();

        // Verify voting power
        uint256 aliceVotingPower = veELTA.votingPower(alice);
        uint256 bobVotingPower = veELTA.votingPower(bob);
        uint256 charlieVotingPower = veELTA.votingPower(charlie);

        assertEq(aliceVotingPower, 50000 ether); // Full amount (max lock)
        assertApproxEqRel(bobVotingPower, 15000 ether, 0.01e18); // ~50% of amount
        assertApproxEqRel(charlieVotingPower, 3750 ether, 0.01e18); // ~25% of amount

        // Logging removed to avoid compilation issues
    }

    function _earnXP() internal {
        // Simulate XP earning through various activities
        vm.startPrank(admin);

        // Alice earns XP for EEG data submission
        xp.award(alice, 2000 ether);

        // Bob earns XP for app usage
        xp.award(bob, 1500 ether);

        // Charlie earns XP for community participation
        xp.award(charlie, 800 ether);

        vm.stopPrank();

        // Verify XP balances
        assertEq(xp.balanceOf(alice), 2000 ether);
        assertEq(xp.balanceOf(bob), 1500 ether);
        assertEq(xp.balanceOf(charlie), 800 ether);

        // Verify voting power (XP auto-delegates to self)
        assertEq(xp.getVotes(alice), 2000 ether);
        assertEq(xp.getVotes(bob), 1500 ether);
        assertEq(xp.getVotes(charlie), 800 ether);
    }

    function _fundLotPool() internal {
        uint256 fundingAmount = 100000 ether;

        vm.startPrank(treasury);
        elta.approve(address(lotPool), fundingAmount);
        lotPool.fund(fundingAmount);
        vm.stopPrank();

        assertEq(elta.balanceOf(address(lotPool)), fundingAmount);
    }

    function _startFundingRound() internal returns (uint256 roundId) {
        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("PTSD_RESEARCH");
        options[1] = keccak256("DEPRESSION_STUDY");

        address[] memory recipients = new address[](2);
        recipients[0] = researcher1;
        recipients[1] = researcher2;

        vm.prank(admin);
        (roundId,) = lotPool.startRound(options, recipients, 7 days);

        assertEq(roundId, 1);
        assertEq(lotPool.currentRoundId(), 1);

        // Logging removed to avoid compilation issues
    }

    function _voteInRound(uint256 roundId) internal {
        bytes32 ptsdOption = keccak256("PTSD_RESEARCH");
        bytes32 depressionOption = keccak256("DEPRESSION_STUDY");

        // Alice votes heavily for PTSD research
        vm.prank(alice);
        lotPool.vote(roundId, ptsdOption, 1800 ether);

        // Bob splits vote between both
        vm.startPrank(bob);
        lotPool.vote(roundId, ptsdOption, 800 ether);
        lotPool.vote(roundId, depressionOption, 700 ether);
        vm.stopPrank();

        // Charlie votes for depression study
        vm.prank(charlie);
        lotPool.vote(roundId, depressionOption, 800 ether);

        // Verify vote tallies
        uint256 ptsdVotes = lotPool.votesFor(roundId, ptsdOption);
        uint256 depressionVotes = lotPool.votesFor(roundId, depressionOption);

        assertEq(ptsdVotes, 2600 ether); // Alice: 1800 + Bob: 800
        assertEq(depressionVotes, 1500 ether); // Bob: 700 + Charlie: 800

        // Logging removed to avoid compilation issues
    }

    function _finalizeRound(uint256 roundId) internal {
        // Fast forward past round end
        vm.warp(block.timestamp + 8 days);

        bytes32 winner = keccak256("PTSD_RESEARCH"); // PTSD research won
        uint256 payoutAmount = 50000 ether;

        uint256 initialBalance = elta.balanceOf(researcher1);

        vm.prank(admin);
        lotPool.finalize(roundId, winner, payoutAmount);

        assertEq(elta.balanceOf(researcher1), initialBalance + payoutAmount);

        // Verify round is finalized
        (,,, bool finalized,) = lotPool.getRound(roundId);
        assertTrue(finalized);

        // Logging removed to avoid compilation issues
    }

    function _testWithdrawal() internal {
        // Fast forward to after Charlie's lock expires (26 weeks)
        vm.warp(block.timestamp + 27 weeks);

        uint256 charlieInitialBalance = elta.balanceOf(charlie);

        vm.prank(charlie);
        veELTA.withdraw();

        assertEq(elta.balanceOf(charlie), charlieInitialBalance + 15000 ether);

        // Verify lock is cleared
        (uint128 amount,,) = veELTA.locks(charlie);
        assertEq(amount, 0);

        // Logging removed to avoid compilation issues
    }

    function test_VotingPowerDecay() public {
        // Alice stakes for 1 year
        vm.startPrank(alice);
        elta.approve(address(veELTA), 10000 ether);
        veELTA.createLock(10000 ether, 52 weeks);
        vm.stopPrank();

        uint256 initialPower = veELTA.votingPower(alice);

        // Fast forward 6 months
        vm.warp(block.timestamp + 26 weeks);
        uint256 halfwayPower = veELTA.votingPower(alice);

        // Fast forward to near end
        vm.warp(block.timestamp + 25 weeks);
        uint256 nearEndPower = veELTA.votingPower(alice);

        // Fast forward past end
        vm.warp(block.timestamp + 2 weeks);
        uint256 expiredPower = veELTA.votingPower(alice);

        // Logging removed to avoid compilation issues

        // Verify decay pattern
        assertGt(initialPower, halfwayPower);
        assertGt(halfwayPower, nearEndPower);
        assertEq(expiredPower, 0);
    }

    function test_XPCheckpoints() public {
        // Award initial XP
        vm.prank(admin);
        xp.award(alice, 1000 ether);

        vm.roll(block.number + 1);
        uint256 block1 = block.number - 1;

        // Mine some blocks and award more XP
        vm.roll(block.number + 4);
        vm.prank(admin);
        xp.award(alice, 500 ether);

        vm.roll(block.number + 1);
        uint256 block2 = block.number - 1;

        // Mine more blocks and revoke some XP
        vm.roll(block.number + 2);
        vm.prank(admin);
        xp.revoke(alice, 200 ether);

        vm.roll(block.number + 1);
        uint256 block3 = block.number - 1;

        // Verify historical balances
        assertEq(xp.getPastXP(alice, block1), 1000 ether);
        assertEq(xp.getPastXP(alice, block2), 1500 ether);
        assertEq(xp.getPastXP(alice, block3), 1300 ether);
        assertEq(xp.balanceOf(alice), 1300 ether);

        // Logging removed to avoid compilation issues
    }

    function test_MultipleRoundsFlow() public {
        // Setup initial state
        vm.prank(admin);
        xp.award(alice, 1000 ether);

        _fundLotPool();

        // Advance block to ensure XP is available for snapshot
        vm.roll(block.number + 1);

        // Round 1
        bytes32[] memory options1 = new bytes32[](1);
        options1[0] = keccak256("ROUND_1_OPTION");

        address[] memory recipients1 = new address[](1);
        recipients1[0] = researcher1;

        vm.prank(admin);
        (uint256 round1Id,) = lotPool.startRound(options1, recipients1, 7 days);

        vm.prank(alice);
        lotPool.vote(round1Id, options1[0], 500 ether);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        lotPool.finalize(round1Id, options1[0], 10000 ether);

        // Round 2 - Alice earns more XP between rounds
        vm.prank(admin);
        xp.award(alice, 500 ether);

        // Advance block again for second round
        vm.roll(block.number + 1);

        bytes32[] memory options2 = new bytes32[](1);
        options2[0] = keccak256("ROUND_2_OPTION");

        address[] memory recipients2 = new address[](1);
        recipients2[0] = researcher2;

        vm.prank(admin);
        (uint256 round2Id,) = lotPool.startRound(options2, recipients2, 7 days);

        // Alice can use her remaining XP from round 1 + new XP in round 2
        vm.prank(alice);
        lotPool.vote(round2Id, options2[0], 1000 ether); // 500 remaining + 500 new

        assertEq(round1Id, 1);
        assertEq(round2Id, 2);
        assertEq(lotPool.votesFor(round2Id, options2[0]), 1000 ether);
    }

    function test_AccessControl() public {
        // Test unauthorized minting
        vm.expectRevert();
        vm.prank(alice);
        elta.mint(alice, 1000 ether);

        // Test unauthorized XP awarding
        vm.expectRevert();
        vm.prank(alice);
        xp.award(alice, 1000 ether);

        // Test unauthorized round starting
        bytes32[] memory options = new bytes32[](1);
        options[0] = keccak256("TEST");

        address[] memory recipients = new address[](1);
        recipients[0] = researcher1;

        vm.expectRevert();
        vm.prank(alice);
        lotPool.startRound(options, recipients, 7 days);
    }

    function test_TokenTransferability() public {
        // ELTA should be transferable
        vm.prank(alice);
        elta.transfer(bob, 1000 ether);
        assertEq(elta.balanceOf(bob), 51000 ether);

        // XP should not be transferable
        vm.prank(admin);
        xp.award(alice, 1000 ether);

        vm.expectRevert();
        vm.prank(alice);
        xp.transfer(bob, 500 ether);
    }
}
