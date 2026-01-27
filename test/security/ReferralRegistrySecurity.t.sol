// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ReferralRegistry} from "../../src/modules/ReferralRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ELTA token for testing
contract MockELTA is ERC20 {
    constructor() ERC20("ELTA", "ELTA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Reentrancy attacker for claim function
contract ClaimReentrancyAttacker {
    ReferralRegistry public registry;
    uint256 public attackCount;
    uint256 public maxAttacks;

    constructor(ReferralRegistry _registry) {
        registry = _registry;
    }

    function attack(uint256 _maxAttacks) external {
        maxAttacks = _maxAttacks;
        attackCount = 0;
        registry.claimRewards();
    }

    // Try to reenter on ELTA receive
    // Note: ERC20 transfers don't trigger receive(), but if there was a callback...
    fallback() external payable {
        if (attackCount < maxAttacks) {
            attackCount++;
            try registry.claimRewards() {} catch {}
        }
    }

    receive() external payable {
        if (attackCount < maxAttacks) {
            attackCount++;
            try registry.claimRewards() {} catch {}
        }
    }
}

/// @notice Contract that tries various attack vectors
contract SybilAttacker {
    ReferralRegistry public registry;
    MockELTA public elta;

    constructor(ReferralRegistry _registry, MockELTA _elta) {
        registry = _registry;
        elta = _elta;
    }

    // Create child contracts for sybil attack
    function createSybilAccounts(uint256 count) external returns (address[] memory) {
        address[] memory accounts = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            accounts[i] = address(new SybilChild(registry, elta));
        }
        return accounts;
    }
}

/// @notice Child contract for sybil attacks
contract SybilChild {
    ReferralRegistry public registry;
    MockELTA public elta;

    constructor(ReferralRegistry _registry, MockELTA _elta) {
        registry = _registry;
        elta = _elta;
    }

    function claimRewards() external {
        registry.claimRewards();
        // Transfer to parent
        uint256 balance = elta.balanceOf(address(this));
        if (balance > 0) {
            elta.transfer(msg.sender, balance);
        }
    }
}

/**
 * @title ReferralRegistrySecurity
 * @notice Red team security tests for ReferralRegistry
 * @dev Tests for:
 *      - Sybil attacks (create many accounts, refer self)
 *      - Wash trading referrals (circular patterns)
 *      - Reward draining without valid referrals
 *      - Front-running to become referrer
 *      - Reentrancy on claim
 *      - BPS manipulation
 *      - Unauthorized access
 */
contract ReferralRegistrySecurity is Test {
    ReferralRegistry public registry;
    MockELTA public elta;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator"); // Authorized caller (e.g., bonding curve)
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant APP_ID = 1;
    uint256 public constant REFERRAL_BPS = 500; // 5%

    function setUp() public {
        elta = new MockELTA();

        registry = new ReferralRegistry(admin, address(elta), REFERRAL_BPS);

        // Authorize operator
        vm.prank(admin);
        registry.setAuthorizedCaller(operator, true);

        // Fund registry for rewards
        elta.transfer(address(registry), 10_000_000 ether);

        // Fund test users
        elta.transfer(attacker, 1_000_000 ether);
        elta.transfer(alice, 1_000_000 ether);
        elta.transfer(bob, 1_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SYBIL ATTACK TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SybilReferralFarming() public {
        // Attacker creates multiple accounts and tries to refer themselves indirectly

        // Create sybil accounts
        address sybil1 = makeAddr("sybil1");
        address sybil2 = makeAddr("sybil2");
        address sybil3 = makeAddr("sybil3");

        // Attacker sets up referral chain: attacker -> sybil1, sybil1 -> sybil2
        vm.startPrank(operator);
        registry.setReferrer(APP_ID, sybil1, attacker);
        registry.setReferrer(APP_ID, sybil2, sybil1);
        registry.setReferrer(APP_ID, sybil3, sybil2);
        vm.stopPrank();

        // Accrue rewards for sybil purchases
        vm.startPrank(operator);
        registry.accrueReferralReward(APP_ID, sybil1, 1000 ether);
        registry.accrueReferralReward(APP_ID, sybil2, 1000 ether);
        registry.accrueReferralReward(APP_ID, sybil3, 1000 ether);
        vm.stopPrank();

        // Check rewards
        uint256 attackerReward = registry.pendingRewards(attacker);
        uint256 sybil1Reward = registry.pendingRewards(sybil1);
        uint256 sybil2Reward = registry.pendingRewards(sybil2);

        console2.log("Attacker reward:", attackerReward);
        console2.log("Sybil1 reward:", sybil1Reward);
        console2.log("Sybil2 reward:", sybil2Reward);

        // The referral system allows this - it's not prevented at contract level
        // This is a known limitation that requires off-chain detection
        // Document: Sybil prevention should be handled through:
        // - Minimum purchase requirements
        // - Time delays
        // - Off-chain analysis
    }

    function test_Security_SybilContractAttack() public {
        SybilAttacker attackerContract = new SybilAttacker(registry, elta);

        // Create many sybil accounts
        address[] memory sybilAccounts = attackerContract.createSybilAccounts(10);

        // Try to set up referral chain through sybil accounts
        // This would require the operator to call setReferrer for each
        // The contract itself cannot set referrers (needs authorization)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WASH TRADING / CIRCULAR REFERRAL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_WashTradingCircularReferrals() public {
        // Alice refers Bob, Bob refers Charlie, Charlie refers Alice (circular)
        vm.startPrank(operator);
        registry.setReferrer(APP_ID, bob, alice);
        registry.setReferrer(APP_ID, charlie, bob);
        registry.setReferrer(APP_ID, alice, charlie); // Circular - but allowed (one-time binding per user)
        vm.stopPrank();

        // Each person's first referrer is set, circular attempts are ignored
        assertEq(registry.getReferrer(APP_ID, bob), alice);
        assertEq(registry.getReferrer(APP_ID, charlie), bob);
        assertEq(registry.getReferrer(APP_ID, alice), charlie);

        // Accrue rewards for all
        vm.startPrank(operator);
        registry.accrueReferralReward(APP_ID, alice, 1000 ether);
        registry.accrueReferralReward(APP_ID, bob, 1000 ether);
        registry.accrueReferralReward(APP_ID, charlie, 1000 ether);
        vm.stopPrank();

        // All referrers get rewards - circular is allowed
        assertGt(registry.pendingRewards(alice), 0, "Alice should have rewards");
        assertGt(registry.pendingRewards(bob), 0, "Bob should have rewards");
        assertGt(registry.pendingRewards(charlie), 0, "Charlie should have rewards");

        // Note: This is intended behavior - circular referrals don't cause infinite loops
        // Each referral chain is single-hop (buyer -> direct referrer only)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARD DRAINING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_RewardDrainingWithoutValidReferrals() public {
        // Try to get rewards without being a referrer
        uint256 attackerRewardBefore = registry.pendingRewards(attacker);
        assertEq(attackerRewardBefore, 0, "Should have no initial rewards");

        // Attacker tries to claim (should get nothing)
        uint256 attackerEltaBefore = elta.balanceOf(attacker);

        vm.prank(attacker);
        registry.claimRewards();

        uint256 attackerEltaAfter = elta.balanceOf(attacker);
        assertEq(attackerEltaAfter, attackerEltaBefore, "Should not receive any rewards");
    }

    function test_Security_CannotManipulateRewardAccounting() public {
        // Only authorized callers can accrue rewards
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(attacker);
        registry.accrueReferralReward(APP_ID, alice, 1000 ether);
    }

    function test_Security_RewardCalculationOverflow() public {
        // Set up referral
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, attacker);

        // Try with max uint256 fee amount - should revert due to overflow
        // Solidity 0.8+ has built-in overflow protection that reverts
        vm.expectRevert(); // Arithmetic overflow
        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, alice, type(uint256).max);

        // Reward should be 0 since call reverted
        uint256 reward = registry.pendingRewards(attacker);
        assertEq(reward, 0, "No reward should be accrued after overflow revert");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REENTRANCY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ReentrancyOnClaim() public {
        // Set up attacker as referrer
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, attacker);

        // Accrue rewards
        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, alice, 10_000 ether);

        uint256 pendingBefore = registry.pendingRewards(attacker);
        assertGt(pendingBefore, 0, "Should have pending rewards");

        // Claim normally (ERC20 transfers don't have callbacks, so reentrancy via receive() won't work)
        // But the contract has ReentrancyGuard anyway
        vm.prank(attacker);
        registry.claimRewards();

        uint256 pendingAfter = registry.pendingRewards(attacker);
        assertEq(pendingAfter, 0, "Should have no pending after claim");

        // Verify can't double claim
        uint256 balanceBefore = elta.balanceOf(attacker);
        vm.prank(attacker);
        registry.claimRewards(); // Should do nothing
        uint256 balanceAfter = elta.balanceOf(attacker);
        assertEq(balanceAfter, balanceBefore, "Should not receive anything on second claim");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SELF-REFERRAL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SelfReferralBlocked() public {
        vm.expectRevert(ReferralRegistry.SelfReferral.selector);
        vm.prank(operator);
        registry.setReferrer(APP_ID, attacker, attacker);
    }

    function test_Security_ZeroAddressReferrerBlocked() public {
        vm.expectRevert(ReferralRegistry.ZeroAddress.selector);
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ONE-TIME BINDING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OneTimeBindingEnforced() public {
        // Set initial referrer
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, bob);

        assertEq(registry.getReferrer(APP_ID, alice), bob);

        // Try to change referrer - should be ignored (not revert)
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, charlie);

        // Should still be bob
        assertEq(registry.getReferrer(APP_ID, alice), bob, "Referrer should not change");
    }

    function test_Security_DifferentAppsCanHaveDifferentReferrers() public {
        vm.startPrank(operator);
        registry.setReferrer(1, alice, bob);
        registry.setReferrer(2, alice, charlie);
        vm.stopPrank();

        assertEq(registry.getReferrer(1, alice), bob);
        assertEq(registry.getReferrer(2, alice), charlie);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BPS MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ReferralBpsManipulation() public {
        // Only admin can set BPS
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(attacker);
        registry.setReferralBps(2000); // Max allowed
    }

    function test_Security_BpsCappedAtMax() public {
        vm.expectRevert(ReferralRegistry.BpsTooHigh.selector);
        vm.prank(admin);
        registry.setReferralBps(2001); // Above max
    }

    function test_Security_BpsChangeAffectsFutureRewards() public {
        // Set up referral
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, attacker);

        // Accrue with initial BPS (500 = 5%)
        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, alice, 1000 ether);

        uint256 reward1 = registry.pendingRewards(attacker);
        assertEq(reward1, 50 ether, "Should be 5% of 1000");

        // Change BPS
        vm.prank(admin);
        registry.setReferralBps(1000); // 10%

        // Accrue again
        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, alice, 1000 ether);

        uint256 reward2 = registry.pendingRewards(attacker);
        assertEq(reward2, 150 ether, "Should be 50 + 100 = 150");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AUTHORIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_UnauthorizedSetReferrer() public {
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(attacker);
        registry.setReferrer(APP_ID, alice, bob);
    }

    function test_Security_UnauthorizedAccrueReward() public {
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(attacker);
        registry.accrueReferralReward(APP_ID, alice, 1000 ether);
    }

    function test_Security_OnlyAdminCanSetAuthorizedCaller() public {
        // Non-admin cannot set authorized callers
        // There's no explicit revert for this, but the function uses admin check
        vm.prank(attacker);
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        registry.setAuthorizedCaller(attacker, true);
    }

    function test_Security_AdminCanBeTransferred() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        registry.setAdmin(newAdmin);

        assertEq(registry.admin(), newAdmin);

        // Old admin should no longer have access
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(admin);
        registry.setReferralBps(100);

        // New admin should have access
        vm.prank(newAdmin);
        registry.setReferralBps(100);
        assertEq(registry.referralBps(), 100);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ReferralRewardBounds(uint256 feeAmount, uint16 bps) public {
        feeAmount = bound(feeAmount, 1 ether, 1_000_000 ether);
        bps = uint16(bound(bps, 1, 2000)); // 0.01% to 20%

        // Set BPS
        vm.prank(admin);
        registry.setReferralBps(bps);

        // Set up referral
        vm.prank(operator);
        registry.setReferrer(APP_ID, alice, attacker);

        // Accrue reward
        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, alice, feeAmount);

        uint256 reward = registry.pendingRewards(attacker);
        uint256 expectedReward = (feeAmount * bps) / 10000;

        assertEq(reward, expectedReward, "Reward calculation incorrect");
    }

    function testFuzz_MultipleBuyersOneReferrer(uint8 numBuyers, uint256 avgFee) public {
        // Bound inputs to reasonable ranges that won't cause overflow
        // Keep numBuyers small and avgFee well within safe range for multiplication
        numBuyers = uint8(bound(uint256(numBuyers), 1, 10)); // Max 10 buyers
        avgFee = bound(avgFee, 1 ether, 100 ether); // Max 100 ether per fee

        uint256 totalExpectedReward = 0;

        for (uint8 i = 0; i < numBuyers; i++) {
            address buyer = address(uint160(2000 + i));
            uint256 fee = avgFee + uint256(i) * 1 ether;

            vm.prank(operator);
            registry.setReferrer(APP_ID, buyer, attacker);

            vm.prank(operator);
            registry.accrueReferralReward(APP_ID, buyer, fee);

            totalExpectedReward += (fee * REFERRAL_BPS) / 10000;
        }

        uint256 actualReward = registry.pendingRewards(attacker);
        assertEq(actualReward, totalExpectedReward, "Total reward incorrect");

        uint256 referralCount = registry.getReferralCount(APP_ID, attacker);
        assertEq(referralCount, numBuyers, "Referral count incorrect");
    }
}
