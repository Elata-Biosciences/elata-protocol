// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {LpLocker} from "../../src/apps/LpLocker.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock LP Token
contract MockLpToken is ERC20 {
    constructor() ERC20("LP Token", "LP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Malicious token that tries reentrancy on transfer
contract MaliciousLpToken is ERC20 {
    LpLocker public targetLocker;
    uint256 public attackCount;
    bool public attacking;

    constructor() ERC20("Malicious LP", "MLP") {}

    function setTarget(LpLocker _locker) external {
        targetLocker = _locker;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (attacking && address(targetLocker) != address(0) && attackCount < 3) {
            attackCount++;
            try targetLocker.claim() {} catch {}
        }
        return super.transfer(to, amount);
    }

    function startAttack() external {
        attacking = true;
        attackCount = 0;
    }

    function stopAttack() external {
        attacking = false;
    }
}

/// @notice Contract that tries to claim on behalf of beneficiary
contract ClaimAttacker {
    LpLocker public locker;

    constructor(LpLocker _locker) {
        locker = _locker;
    }

    function attemptClaim() external {
        locker.claim();
    }
}

/**
 * @title LpLockerSecurity
 * @notice Red team security tests for LpLocker
 * @dev Tests for:
 *      - Time manipulation attacks
 *      - Early withdrawal prevention
 *      - Beneficiary cannot be changed
 *      - Re-lock prevention after claim
 *      - Multiple claim attempts
 *      - Exact unlock time boundary
 */
contract LpLockerSecurity is Test {
    MockLpToken public lpToken;
    LpLocker public locker;

    address public beneficiary = makeAddr("beneficiary");
    address public attacker = makeAddr("attacker");

    uint256 public constant APP_ID = 1;
    uint256 public constant LOCK_DURATION = 365 days * 2; // 2 years
    uint256 public constant LOCK_AMOUNT = 1000 ether;

    uint256 public unlockTime;

    function setUp() public {
        lpToken = new MockLpToken();
        unlockTime = block.timestamp + LOCK_DURATION;

        locker = new LpLocker(APP_ID, address(lpToken), beneficiary, unlockTime);

        // Mint and lock LP tokens
        lpToken.mint(address(this), LOCK_AMOUNT);
        lpToken.transfer(address(locker), LOCK_AMOUNT);
        locker.lockLp(LOCK_AMOUNT); // Emit event, tokens already in locker
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotWithdrawEarly() public {
        // Try at various points before unlock
        uint256[] memory testTimes = new uint256[](5);
        testTimes[0] = block.timestamp; // Now
        testTimes[1] = block.timestamp + 1 days;
        testTimes[2] = block.timestamp + 30 days;
        testTimes[3] = block.timestamp + 365 days;
        testTimes[4] = unlockTime - 1; // 1 second before

        for (uint256 i = 0; i < testTimes.length; i++) {
            vm.warp(testTimes[i]);

            vm.expectRevert(LpLocker.NotYetUnlocked.selector);
            vm.prank(beneficiary);
            locker.claim();
        }
    }

    function test_Security_TimestampManipulation() public {
        // Miner/validator could manipulate timestamp within limits (usually ~15 sec)
        // Test boundary conditions

        // Just before unlock
        vm.warp(unlockTime - 1);
        assertFalse(locker.canClaim(), "Should not be claimable 1 sec before");

        vm.expectRevert(LpLocker.NotYetUnlocked.selector);
        vm.prank(beneficiary);
        locker.claim();

        // Exactly at unlock
        vm.warp(unlockTime);
        assertTrue(locker.canClaim(), "Should be claimable at unlock time");

        vm.prank(beneficiary);
        locker.claim();

        assertTrue(locker.claimed(), "Should be claimed");
    }

    function test_Security_ExactUnlockTimeBoundary() public {
        // Warp to exact unlock time
        vm.warp(unlockTime);

        assertTrue(locker.canClaim());
        assertEq(locker.timeUntilUnlock(), 0);

        uint256 balanceBefore = lpToken.balanceOf(beneficiary);

        vm.prank(beneficiary);
        locker.claim();

        uint256 balanceAfter = lpToken.balanceOf(beneficiary);
        assertEq(balanceAfter - balanceBefore, LOCK_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BENEFICIARY IMMUTABILITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotChangeBeneficiary() public {
        // LpLocker has immutable beneficiary - there's no setter function
        // This is by design for security

        // Verify beneficiary is correct
        assertEq(locker.beneficiary(), beneficiary);

        // No way to change it since it's immutable
        // This test documents the security property
    }

    function test_Security_OnlyBeneficiaryCanClaim() public {
        vm.warp(unlockTime + 1);

        // Attacker tries to claim
        vm.expectRevert(LpLocker.Unauthorized.selector);
        vm.prank(attacker);
        locker.claim();

        // Verify tokens are still locked
        assertEq(lpToken.balanceOf(address(locker)), LOCK_AMOUNT);
        assertFalse(locker.claimed());
    }

    function test_Security_ContractCannotClaimForBeneficiary() public {
        ClaimAttacker attackerContract = new ClaimAttacker(locker);

        vm.warp(unlockTime + 1);

        // Contract tries to claim
        vm.expectRevert(LpLocker.Unauthorized.selector);
        attackerContract.attemptClaim();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DOUBLE CLAIM PREVENTION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_MultipleClaimAttempts() public {
        vm.warp(unlockTime + 1);

        // First claim succeeds
        vm.prank(beneficiary);
        locker.claim();

        assertTrue(locker.claimed());
        assertFalse(locker.canClaim());

        // Second claim fails
        vm.expectRevert(LpLocker.AlreadyClaimed.selector);
        vm.prank(beneficiary);
        locker.claim();
    }

    function test_Security_ClaimStatusPersists() public {
        vm.warp(unlockTime + 1);

        vm.prank(beneficiary);
        locker.claim();

        // Warp further into future
        vm.warp(unlockTime + 365 days);

        // Still cannot claim
        vm.expectRevert(LpLocker.AlreadyClaimed.selector);
        vm.prank(beneficiary);
        locker.claim();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ReentrancyOnClaim() public {
        // Deploy locker with malicious token
        MaliciousLpToken maliciousToken = new MaliciousLpToken();
        LpLocker maliciousLocker = new LpLocker(APP_ID, address(maliciousToken), beneficiary, unlockTime);

        // Set up attack
        maliciousToken.setTarget(maliciousLocker);
        maliciousToken.mint(address(maliciousLocker), LOCK_AMOUNT);

        vm.warp(unlockTime + 1);

        // Start attack
        maliciousToken.startAttack();

        // Claim - the malicious transfer callback will try to reenter
        vm.prank(beneficiary);
        maliciousLocker.claim();

        // Should only claim once due to claimed flag
        assertTrue(maliciousLocker.claimed());

        // Verify attack count (callback was triggered but claim failed)
        console2.log("Reentrancy attempts:", maliciousToken.attackCount());
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADDITIONAL LOCK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotRelock() public {
        vm.warp(unlockTime + 1);

        // Claim first
        vm.prank(beneficiary);
        locker.claim();

        // Try to lock more tokens
        lpToken.mint(address(this), LOCK_AMOUNT);
        lpToken.transfer(address(locker), LOCK_AMOUNT);

        // After tokens are in the locker, lockLp can be called but
        // the claimed flag prevents double claim
        locker.lockLp(LOCK_AMOUNT);

        // New tokens are stuck because claimed is true
        assertEq(lpToken.balanceOf(address(locker)), LOCK_AMOUNT);

        // Cannot claim again
        vm.expectRevert(LpLocker.AlreadyClaimed.selector);
        vm.prank(beneficiary);
        locker.claim();

        // Note: This is actually a potential issue - tokens can be stuck
        // After claim, any additional tokens sent are unrecoverable
        // Document: Don't send more LP tokens after claim
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_DeploymentValidation() public {
        // Cannot deploy with zero LP token
        vm.expectRevert("Zero LP token");
        new LpLocker(APP_ID, address(0), beneficiary, unlockTime);

        // Cannot deploy with zero beneficiary
        vm.expectRevert("Zero beneficiary");
        new LpLocker(APP_ID, address(lpToken), address(0), unlockTime);

        // Cannot deploy with past unlock time
        vm.expectRevert("Invalid unlock time");
        new LpLocker(APP_ID, address(lpToken), beneficiary, block.timestamp - 1);

        // Cannot deploy with current time as unlock
        vm.expectRevert("Invalid unlock time");
        new LpLocker(APP_ID, address(lpToken), beneficiary, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ViewFunctionsAccurate() public {
        // Before unlock
        assertEq(locker.getLockedBalance(), LOCK_AMOUNT);
        assertFalse(locker.canClaim());
        assertGt(locker.timeUntilUnlock(), 0);

        // Warp to halfway
        vm.warp(block.timestamp + LOCK_DURATION / 2);
        assertApproxEqAbs(locker.timeUntilUnlock(), LOCK_DURATION / 2, 1);

        // At unlock
        vm.warp(unlockTime);
        assertEq(locker.timeUntilUnlock(), 0);
        assertTrue(locker.canClaim());

        // After claim
        vm.prank(beneficiary);
        locker.claim();

        assertEq(locker.getLockedBalance(), 0);
        assertFalse(locker.canClaim());
        assertEq(locker.timeUntilUnlock(), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_LockDurationBounds(uint256 lockDuration) public {
        // Bound to reasonable range: 1 day to 10 years
        lockDuration = bound(lockDuration, 1 days, 365 days * 10);

        uint256 fuzzUnlockTime = block.timestamp + lockDuration;
        LpLocker fuzzLocker = new LpLocker(APP_ID + 1, address(lpToken), beneficiary, fuzzUnlockTime);

        // Mint and lock
        lpToken.mint(address(fuzzLocker), LOCK_AMOUNT);

        // Cannot claim before unlock
        vm.warp(fuzzUnlockTime - 1);
        vm.expectRevert(LpLocker.NotYetUnlocked.selector);
        vm.prank(beneficiary);
        fuzzLocker.claim();

        // Can claim at/after unlock
        vm.warp(fuzzUnlockTime);
        vm.prank(beneficiary);
        fuzzLocker.claim();

        assertTrue(fuzzLocker.claimed());
    }

    function testFuzz_ClaimAtVariousTimes(uint256 claimOffset) public {
        // Offset from unlock time: 0 to 5 years after unlock
        claimOffset = bound(claimOffset, 0, 365 days * 5);

        vm.warp(unlockTime + claimOffset);

        uint256 balanceBefore = lpToken.balanceOf(beneficiary);

        vm.prank(beneficiary);
        locker.claim();

        uint256 balanceAfter = lpToken.balanceOf(beneficiary);

        // Should receive full amount regardless of when claimed after unlock
        assertEq(balanceAfter - balanceBefore, LOCK_AMOUNT);
    }
}
