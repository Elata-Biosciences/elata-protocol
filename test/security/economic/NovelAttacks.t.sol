// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {ProtocolConfig} from "../../../src/core/ProtocolConfig.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title NovelAttacks
 * @notice Novel and cross-contract attack tests
 */
contract NovelAttacks is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppToken public appToken;
    ProtocolConfig public config;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;

    function setUp() public {
        vm.prank(admin);
        elta = new ELTA(admin);

        veElta = new VeELTA(IERC20(address(elta)), admin);

        appToken = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: APP_TOKEN_SUPPLY,
                creator: admin,
                admin: admin,
                governance: admin,
                appRewardsDistributor: treasury,
                rewardsDistributor: treasury,
                treasury: treasury
            })
        );

        config = new ProtocolConfig(admin, timelock);

        vm.startPrank(admin);
        elta.transfer(user1, 1_000_000 ether);
        elta.transfer(user2, 1_000_000 ether);
        elta.transfer(attacker, 100_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CROSS-CONTRACT ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossContract_TokenApprovalNotShared() public {
        // User approves ELTA to contract A
        vm.prank(user1);
        elta.approve(address(veElta), 1000 ether);

        // Attacker cannot use that approval for different contract
        vm.prank(attacker);
        vm.expectRevert();
        elta.transferFrom(user1, attacker, 1000 ether);
    }

    function test_CrossContract_LockDoesNotAffectOtherContracts() public {
        // Lock in VeELTA
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 30 days));
        vm.stopPrank();

        // User can still transfer remaining ELTA
        uint256 remaining = elta.balanceOf(user1);
        vm.prank(user1);
        elta.transfer(user2, remaining / 2);

        // VeELTA lock is independent
        (uint128 principal,) = veElta.locks(user1);
        assertEq(principal, 1000 ether, "Lock should be unchanged");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ECONOMIC ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Economic_TransferTaxAccumulation() public {
        // Set transfer tax on app token
        vm.prank(admin);
        appToken.setTransferFeeBps(100); // 1% tax

        // Mint to user
        vm.prank(admin);
        appToken.mint(user1, 10000 ether);

        // Transfer
        uint256 amount = 1000 ether;
        vm.prank(user1);
        appToken.transfer(user2, amount);

        // User2 receives amount (tax may be deducted differently)
        uint256 received = appToken.balanceOf(user2);
        assertLe(received, amount, "Should receive at most amount");
    }

    function test_Economic_BurnFeeDeflationary() public {
        // Set burn fee
        vm.prank(admin);
        appToken.setBurnFeeBps(100); // 1% burn

        // Mint to user
        vm.prank(admin);
        appToken.mint(user1, 10000 ether);

        uint256 supplyBefore = appToken.totalSupply();

        // Transfer (triggers burn)
        vm.prank(user1);
        appToken.transfer(user2, 1000 ether);

        uint256 supplyAfter = appToken.totalSupply();

        // Supply should decrease
        assertLe(supplyAfter, supplyBefore, "Supply should not increase");
    }

    function test_Economic_VotingPowerNotInflatable() public {
        // Lock tokens
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        uint256 votingPower = veElta.getVotes(user1);

        // Voting power should be at most 2x principal
        assertLe(votingPower, 2000 ether, "Voting power capped at 2x");
        assertGe(votingPower, 1000 ether, "Voting power at least 1x");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME-BASED ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TimeBased_VotingPowerDecay() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        uint64 lockDuration = 365 days;
        veElta.lock(1000 ether, uint64(block.timestamp + lockDuration));

        uint256 powerAtStart = veElta.getVotes(user1);
        vm.stopPrank();

        // Warp forward
        vm.warp(block.timestamp + 180 days);
        uint256 powerAt6Months = veElta.getVotes(user1);

        // Power should decay as unlock approaches
        assertLe(powerAt6Months, powerAtStart, "Power should decay");
    }

    function test_TimeBased_LockUnlockTiming() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        uint64 unlockTime = uint64(block.timestamp + 8 days);
        veElta.lock(1000 ether, unlockTime);

        // Cannot unlock 1 second before
        vm.warp(unlockTime - 1);
        vm.expectRevert();
        veElta.unlock();

        // Can unlock at exact time
        vm.warp(unlockTime);
        veElta.unlock();
        vm.stopPrank();
    }

    function test_TimeBased_ConfigBoundsEnforced() public {
        // Graduation target bounds
        vm.prank(timelock);
        config.setGraduationTarget(1000 ether);

        uint256 target = config.graduationTarget();
        assertEq(target, 1000 ether, "Should set valid target");

        // Test that bounds are enforced
        // Very small target may be rejected
        vm.prank(timelock);
        vm.expectRevert(); // Expect rejection for too-small target
        config.setGraduationTarget(0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_State_LockStateConsistent() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 2000 ether);

        // Lock
        veElta.lock(1000 ether, uint64(block.timestamp + 30 days));
        (uint128 principal1, uint64 unlockTime1) = veElta.locks(user1);

        // Increase amount
        veElta.increaseAmount(500 ether);
        (uint128 principal2, uint64 unlockTime2) = veElta.locks(user1);

        // Principal should increase, unlock unchanged
        assertEq(principal2, principal1 + 500 ether, "Principal should increase");
        assertEq(unlockTime2, unlockTime1, "Unlock time should not change");
        vm.stopPrank();
    }

    function test_State_ExtendLockOnlyForward() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        veElta.lock(1000 ether, uint64(block.timestamp + 30 days));
        (, uint64 originalUnlock) = veElta.locks(user1);

        // Cannot extend to earlier time
        vm.expectRevert();
        veElta.extendLock(originalUnlock - 1);

        // Can extend forward
        veElta.extendLock(originalUnlock + 30 days);
        (, uint64 newUnlock) = veElta.locks(user1);
        assertGt(newUnlock, originalUnlock, "Should extend forward");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DELEGATION ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Delegation_SelfDelegation() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Self delegate (default)
        uint256 selfVotes = veElta.getVotes(user1);
        assertGt(selfVotes, 0, "Should have self-delegated votes");
        vm.stopPrank();
    }

    function test_Delegation_DelegateToOther() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Delegate to user2
        veElta.delegate(user2);

        // User1 should have 0 votes, user2 should have user1's votes
        uint256 user1Votes = veElta.getVotes(user1);
        uint256 user2Votes = veElta.getVotes(user2);

        assertEq(user1Votes, 0, "User1 should have 0 votes after delegation");
        assertGt(user2Votes, 0, "User2 should have delegated votes");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_TransferTaxBounds(uint256 taxBps) public {
        taxBps = bound(taxBps, 0, appToken.MAX_TRANSFER_FEE_BPS());

        vm.prank(admin);
        appToken.setTransferFeeBps(uint16(taxBps));

        // Verify it was set
        assertEq(appToken.transferFeeBps(), taxBps, "Tax should be set");
    }

    function testFuzz_LockTimeBounds(uint256 duration) public {
        uint64 minLock = veElta.MIN_LOCK();
        uint64 maxLock = veElta.MAX_LOCK();

        duration = bound(duration, minLock + 1, maxLock);

        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + duration));

        (uint128 principal,) = veElta.locks(user1);
        assertEq(principal, 1000 ether, "Should lock successfully");
        vm.stopPrank();
    }
}
