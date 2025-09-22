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
 * @title Economic Security Tests
 * @notice Tests for economic exploits and manipulation attempts
 * @dev Tests flash loan attacks, voting manipulation, and economic edge cases
 */
contract EconomicSecurityTest is Test {
    ELTA public elta;
    VeELTA public staking;
    ElataXP public xp;
    LotPool public funding;
    RewardsDistributor public rewards;
    ElataGovernor public governor;
    
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    FlashLoanAttacker public flashLoanAttacker;
    
    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        xp = new ElataXP(admin);
        staking = new VeELTA(elta, admin);
        funding = new LotPool(elta, xp, admin);
        rewards = new RewardsDistributor(staking, admin);
        governor = new ElataGovernor(elta);
        
        flashLoanAttacker = new FlashLoanAttacker(elta, staking, governor);
        
        // Distribute tokens
        vm.startPrank(treasury);
        elta.transfer(user1, 1_000_000 ether);
        elta.transfer(user2, 500_000 ether);
        elta.transfer(attacker, 100_000 ether);
        elta.transfer(address(flashLoanAttacker), 1_000_000 ether);
        vm.stopPrank();
    }

    function test_Security_FlashLoanGovernanceAttack() public {
        // Attacker tries to use flash loan to manipulate governance
        // This should fail because veELTA requires time-locked positions
        
        uint256 initialVotingPower = staking.getUserVotingPower(address(flashLoanAttacker));
        
        vm.prank(address(flashLoanAttacker));
        flashLoanAttacker.attemptFlashLoanGovernanceAttack();
        
        // Verify voting power is minimal due to time commitment requirement
        uint256 finalVotingPower = staking.getUserVotingPower(address(flashLoanAttacker));
        
        // Should have minimal voting power due to minimum lock requirement
        uint256 flashLoanAmount = elta.balanceOf(address(flashLoanAttacker));
        uint256 expectedMinPower = (flashLoanAmount * staking.MIN_LOCK()) / staking.MAX_LOCK();
        
        assertEq(finalVotingPower, expectedMinPower);
        
        // This makes flash loan attacks economically infeasible
        // because the attacker gets minimal voting power and cannot immediately withdraw
    }

    function test_Security_SupplyCapEnforcement() public {
        // Test that supply cap cannot be exceeded
        uint256 maxSupply = elta.MAX_SUPPLY();
        uint256 currentSupply = elta.totalSupply();
        uint256 remainingMintable = maxSupply - currentSupply;
        
        // Mint up to the cap
        vm.prank(admin);
        elta.mint(user1, remainingMintable);
        
        assertEq(elta.totalSupply(), maxSupply);
        
        // Try to mint one more token - should fail
        vm.expectRevert(Errors.CapExceeded.selector);
        vm.prank(admin);
        elta.mint(user1, 1);
        
        // Supply should remain at cap
        assertEq(elta.totalSupply(), maxSupply);
    }

    function test_Security_VotingPowerManipulation() public {
        // Test that voting power cannot be manipulated through position transfers
        // (positions are non-transferable)
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        
        // Verify user1 has voting power
        uint256 votingPower = staking.getUserVotingPower(user1);
        assertGt(votingPower, 0);
        
        // Try to transfer position to user2 (should fail)
        vm.expectRevert(Errors.TransfersDisabled.selector);
        staking.transferFrom(user1, user2, tokenId);
        
        // Verify voting power didn't change hands
        assertEq(staking.getUserVotingPower(user1), votingPower);
        assertEq(staking.getUserVotingPower(user2), 0);
        vm.stopPrank();
    }

    function test_Security_XPTransferPrevention() public {
        // Award XP to user1
        vm.prank(admin);
        xp.award(user1, 10_000 ether);
        
        // Verify user1 has XP
        assertEq(xp.balanceOf(user1), 10_000 ether);
        
        // Try to transfer XP (should fail - soulbound)
        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user1);
        xp.transfer(user2, 5_000 ether);
        
        // Try transferFrom (should also fail)
        vm.prank(user1);
        xp.approve(user2, 5_000 ether);
        
        vm.expectRevert(Errors.TransfersDisabled.selector);
        vm.prank(user2);
        xp.transferFrom(user1, user2, 5_000 ether);
        
        // Verify XP didn't move
        assertEq(xp.balanceOf(user1), 10_000 ether);
        assertEq(xp.balanceOf(user2), 0);
    }

    function test_Security_VotingDoubleSpending() public {
        // Test that users can't vote with more XP than they have
        
        vm.prank(admin);
        xp.award(user1, 1000 ether);
        
        // Fund the pool
        vm.startPrank(treasury);
        elta.approve(address(funding), 50_000 ether);
        funding.fund(50_000 ether);
        vm.stopPrank();
        
        // Start round
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("OPTION_A");
        options[1] = keccak256("OPTION_B");
        
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        // User1 votes with all their XP on option A
        vm.prank(user1);
        funding.vote(roundId, options[0], 1000 ether);
        
        // User1 tries to vote again on option B (should fail)
        vm.expectRevert(Errors.InsufficientXP.selector);
        vm.prank(user1);
        funding.vote(roundId, options[1], 1 ether);
        
        // Verify only first vote was recorded
        assertEq(funding.votesFor(roundId, options[0]), 1000 ether);
        assertEq(funding.votesFor(roundId, options[1]), 0);
    }

    function test_Security_EmergencyUnlockPenalty() public {
        // Test that emergency unlock properly applies penalty
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        vm.stopPrank();
        
        uint256 initialBalance = elta.balanceOf(user1);
        
        // Enable emergency unlock
        vm.prank(admin);
        staking.setEmergencyUnlockEnabled(true);
        
        // Emergency unlock
        vm.prank(admin);
        staking.emergencyUnlock(tokenId);
        
        // Verify penalty was applied (50% penalty = 50,000 ELTA lost)
        uint256 expectedReturn = 100_000 ether - (100_000 ether * 5000) / 10000;
        assertEq(elta.balanceOf(user1), initialBalance + expectedReturn);
        
        // Verify position is marked as emergency unlocked
        (,,,, bool emergencyUnlocked) = staking.positions(tokenId);
        assertTrue(emergencyUnlocked);
    }

    function test_Security_VotingPowerDecayManipulation() public {
        // Test that voting power cannot be manipulated by gaming time
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        
        uint256 initialPower = staking.getPositionVotingPower(tokenId);
        
        // Fast forward time
        vm.warp(block.timestamp + 26 weeks);
        uint256 halfwayPower = staking.getPositionVotingPower(tokenId);
        
        // Verify power decayed as expected (should be ~25% of initial)
        assertLt(halfwayPower, initialPower);
        uint256 expectedHalfwayPower = (100_000 ether * 26 weeks) / staking.MAX_LOCK();
        assertApproxEqRel(halfwayPower, expectedHalfwayPower, 0.01e18);
        
        vm.stopPrank();
    }

    function test_Security_XPDecayManipulation() public {
        // Test that XP decay cannot be manipulated
        
        vm.prank(admin);
        xp.award(user1, 10_000 ether);
        
        uint256 initialBalance = xp.balanceOf(user1);
        uint256 initialEffective = xp.effectiveBalance(user1);
        
        assertEq(initialBalance, initialEffective);
        
        // Fast forward 7 days
        vm.warp(block.timestamp + 7 days);
        
        uint256 decayedEffective = xp.effectiveBalance(user1);
        assertLt(decayedEffective, initialEffective);
        
        // User cannot prevent decay by calling functions
        vm.prank(user1);
        xp.balanceOf(user1); // Read-only call
        
        // Effective balance should still be decayed
        assertEq(xp.effectiveBalance(user1), decayedEffective);
    }

    function test_Security_ArithmeticOverflowProtection() public {
        // Test protection against arithmetic overflow/underflow
        
        // Try to mint maximum possible amount
        uint256 maxMint = type(uint256).max;
        
        vm.expectRevert(Errors.CapExceeded.selector);
        vm.prank(admin);
        elta.mint(user1, maxMint);
        
        // Try to create lock with maximum amount and duration
        vm.startPrank(user1);
        elta.approve(address(staking), type(uint128).max);
        
        // This should work up to available balance
        uint256 userBalance = elta.balanceOf(user1);
        if (userBalance > 0) {
            uint256 lockAmount = userBalance > 100_000 ether ? 100_000 ether : userBalance;
            uint256 tokenId = staking.createLock(lockAmount, staking.MAX_LOCK());
            
            // Verify position was created correctly
            (uint128 amount,,,, ) = staking.positions(tokenId);
            assertEq(amount, lockAmount);
        }
        vm.stopPrank();
    }

    function test_Security_RewardDistributionIntegrity() public {
        // Test that reward distribution cannot be manipulated
        
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
        
        // Try to finalize epoch too early
        vm.expectRevert(RewardsDistributor.DistributionTooEarly.selector);
        vm.prank(treasury);
        rewards.finalizeEpoch(keccak256("fake_root"));
        
        // Wait proper time and finalize
        vm.warp(block.timestamp + 8 days);
        vm.prank(treasury);
        rewards.finalizeEpoch(keccak256("legitimate_root"));
        
        // Try to finalize again (should fail)
        vm.expectRevert(RewardsDistributor.EpochAlreadyFinalized.selector);
        vm.prank(treasury);
        rewards.finalizeEpoch(keccak256("another_root"));
    }

    function testFuzz_Security_VotingPowerCalculation(
        uint256 amount,
        uint256 duration,
        uint256 timeElapsed
    ) public {
        // Bound inputs to valid ranges
        amount = bound(amount, 1 ether, 1_000_000 ether);
        duration = bound(duration, staking.MIN_LOCK(), staking.MAX_LOCK());
        timeElapsed = bound(timeElapsed, 0, duration);
        
        vm.prank(treasury);
        elta.transfer(user1, amount);
        
        vm.startPrank(user1);
        elta.approve(address(staking), amount);
        uint256 tokenId = staking.createLock(amount, duration);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 votingPower = staking.getPositionVotingPower(tokenId);
        uint256 expectedPower = (amount * (duration - timeElapsed)) / staking.MAX_LOCK();
        
        // Verify calculation is correct and not manipulable
        assertEq(votingPower, expectedPower);
        
        // Verify power is monotonically decreasing
        if (timeElapsed < duration) {
            assertGt(votingPower, 0);
        } else {
            assertEq(votingPower, 0);
        }
    }

    function testFuzz_Security_XPDecayCalculation(
        uint256 amount,
        uint256 timeElapsed
    ) public {
        // Bound inputs
        amount = bound(amount, 1 ether, 1_000_000 ether);
        timeElapsed = bound(timeElapsed, 0, 30 days);
        
        vm.prank(admin);
        xp.award(user1, amount);
        
        // Fast forward time
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 effectiveBalance = xp.effectiveBalance(user1);
        
        // Verify decay calculation
        if (timeElapsed >= xp.DECAY_WINDOW()) {
            assertEq(effectiveBalance, 0);
        } else {
            uint256 expectedEffective = (amount * (xp.DECAY_WINDOW() - timeElapsed)) / xp.DECAY_WINDOW();
            assertApproxEqRel(effectiveBalance, expectedEffective, 0.01e18);
        }
        
        // Verify effective balance is never greater than actual balance
        assertLe(effectiveBalance, xp.balanceOf(user1));
    }

    function test_Security_LotPoolManipulation() public {
        // Test that LotPool voting cannot be manipulated
        
        // Give users XP
        vm.startPrank(admin);
        xp.award(user1, 5000 ether);
        xp.award(user2, 3000 ether);
        vm.stopPrank();
        
        // Fund the pool
        vm.startPrank(treasury);
        elta.approve(address(funding), 100_000 ether);
        funding.fund(100_000 ether);
        vm.stopPrank();
        
        // Start round
        vm.roll(block.number + 1);
        
        bytes32[] memory options = new bytes32[](2);
        options[0] = keccak256("LEGITIMATE_RESEARCH");
        options[1] = keccak256("ATTACKER_PROPOSAL");
        
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = attacker;
        
        vm.prank(admin);
        (uint256 roundId,) = funding.startRound(options, recipients, 7 days);
        
        // Users vote
        vm.prank(user1);
        funding.vote(roundId, options[0], 5000 ether);
        
        vm.prank(user2);
        funding.vote(roundId, options[0], 3000 ether);
        
        // Attacker has no XP, cannot vote
        vm.expectRevert(Errors.InsufficientXP.selector);
        vm.prank(attacker);
        funding.vote(roundId, options[1], 1 ether);
        
        // Verify legitimate option wins
        assertEq(funding.votesFor(roundId, options[0]), 8000 ether);
        assertEq(funding.votesFor(roundId, options[1]), 0);
        
        // Finalize round
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        funding.finalize(roundId, options[0], 50_000 ether);
        
        // Verify legitimate recipient received funds
        assertEq(elta.balanceOf(user1), 1_000_000 ether + 50_000 ether);
        assertEq(elta.balanceOf(attacker), 100_000 ether); // No change
    }

    function test_Security_MerkleProofManipulation() public {
        // Test that merkle proof verification cannot be bypassed
        
        vm.prank(admin);
        rewards.addRewardToken(elta);
        
        // Setup epoch
        vm.startPrank(treasury);
        elta.approve(address(rewards), 100_000 ether);
        vm.stopPrank();
        
        vm.prank(admin);
        rewards.grantRole(rewards.DISTRIBUTOR_ROLE(), treasury);
        
        vm.prank(treasury);
        rewards.depositRewards(address(elta), 100_000 ether);
        
        // Finalize epoch
        vm.warp(block.timestamp + 8 days);
        bytes32 legitimateRoot = keccak256("legitimate_merkle_root");
        vm.prank(treasury);
        rewards.finalizeEpoch(legitimateRoot);
        
        // Attacker tries to claim with invalid proof
        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = keccak256("fake_proof");
        
        vm.expectRevert(RewardsDistributor.InvalidProof.selector);
        vm.prank(attacker);
        rewards.claimRewards(0, 10_000 ether, fakeProof);
        
        // Verify attacker received nothing
        assertEq(elta.balanceOf(attacker), 100_000 ether); // Original amount
    }

    function test_Security_TimeLockBypass() public {
        // Test that time locks cannot be bypassed
        
        vm.startPrank(user1);
        elta.approve(address(staking), 100_000 ether);
        uint256 tokenId = staking.createLock(100_000 ether, 52 weeks);
        
        // Try to withdraw before expiry
        vm.expectRevert(Errors.LockNotExpired.selector);
        staking.withdraw(tokenId);
        
        // Try to extend lock to shorter duration
        vm.expectRevert(Errors.LockTooShort.selector);
        staking.increaseUnlockTime(tokenId, block.timestamp + 26 weeks);
        
        // Try to extend beyond maximum
        vm.expectRevert(Errors.LockTooLong.selector);
        staking.increaseUnlockTime(tokenId, block.timestamp + staking.MAX_LOCK() + 1 weeks);
        
        vm.stopPrank();
    }

    function test_Security_IntegerOverflowProtection() public {
        // Test protection against integer overflow in calculations
        
        // Test voting power calculation with large numbers
        vm.startPrank(user1);
        elta.approve(address(staking), 500_000 ether);
        uint256 tokenId = staking.createLock(500_000 ether, staking.MAX_LOCK());
        
        uint256 votingPower = staking.getPositionVotingPower(tokenId);
        
        // Should not overflow and should equal the locked amount for max lock
        assertEq(votingPower, 500_000 ether);
        assertLe(votingPower, 500_000 ether); // Sanity check
        
        vm.stopPrank();
    }
}

/**
 * @title Flash Loan Attacker Contract
 * @notice Simulates flash loan attacks on governance
 */
contract FlashLoanAttacker {
    ELTA public elta;
    VeELTA public staking;
    ElataGovernor public governor;
    
    constructor(ELTA _elta, VeELTA _staking, ElataGovernor _governor) {
        elta = _elta;
        staking = _staking;
        governor = _governor;
    }
    
    function attemptFlashLoanGovernanceAttack() external {
        // Simulate getting a flash loan of ELTA tokens
        uint256 flashLoanAmount = elta.balanceOf(address(this));
        
        // Try to use flash loaned tokens for governance
        // This should fail because veELTA requires time-locked positions
        
        elta.approve(address(staking), flashLoanAmount);
        
        // Try to create a position and immediately vote
        // This fails because positions are time-locked
        uint256 tokenId = staking.createLock(flashLoanAmount, staking.MIN_LOCK());
        
        // Even with a position, voting power requires time commitment
        uint256 votingPower = staking.getUserVotingPower(address(this));
        
        // For minimum lock, voting power should be minimal
        // Cannot withdraw immediately to repay flash loan
        // This makes flash loan attacks economically infeasible
    }
}
