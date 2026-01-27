// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ReferralRegistry} from "../../src/modules/ReferralRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockELTA is ERC20 {
    constructor() ERC20("ELTA", "ELTA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title ReferralRegistryTest
 * @notice Unit tests for ReferralRegistry contract
 * @dev Tests referral tracking and reward accumulation
 *
 * Per Protocol Changes document section 14:
 * - Referrals apply to bonding curve buys
 * - One-time referrer binding
 * - referrerOf[buyer] stored once
 * - Pay referral from existing fee split
 */
contract ReferralRegistryTest is Test {
    ReferralRegistry public registry;
    MockELTA public elta;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator"); // e.g., bonding curve
    address public feeManager = makeAddr("feeManager");

    // Test users
    address public referrer1 = makeAddr("referrer1");
    address public referrer2 = makeAddr("referrer2");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public attacker = makeAddr("attacker");

    uint256 public constant APP_ID = 1;
    uint256 public constant REFERRAL_BPS = 500; // 5% of fees

    function setUp() public {
        elta = new MockELTA();

        registry = new ReferralRegistry(admin, address(elta), REFERRAL_BPS);

        // Authorize operator (like bonding curve)
        vm.prank(admin);
        registry.setAuthorizedCaller(operator, true);

        // Fund registry for rewards
        elta.transfer(address(registry), 1_000_000 ether);
    }

    // =========== Deployment Tests ===========

    function test_Deploy() public view {
        assertEq(registry.admin(), admin);
        assertEq(address(registry.elta()), address(elta));
        assertEq(registry.referralBps(), REFERRAL_BPS);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(ReferralRegistry.ZeroAddress.selector);
        new ReferralRegistry(address(0), address(elta), REFERRAL_BPS);
    }

    function test_RevertWhen_DeployWithZeroELTA() public {
        vm.expectRevert(ReferralRegistry.ZeroAddress.selector);
        new ReferralRegistry(admin, address(0), REFERRAL_BPS);
    }

    function test_RevertWhen_DeployWithHighBps() public {
        vm.expectRevert(ReferralRegistry.BpsTooHigh.selector);
        new ReferralRegistry(admin, address(elta), 2001); // > 20%
    }

    // =========== Referrer Binding Tests ===========

    function test_SetReferrer() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        assertEq(registry.getReferrer(APP_ID, buyer1), referrer1);
    }

    function test_SetReferrerEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ReferralRegistry.ReferrerSet(APP_ID, buyer1, referrer1);

        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);
    }

    function test_ReferrerBindingIsOneTime() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        // Second call should be ignored (no revert, just no change)
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer2);

        // Should still be referrer1
        assertEq(registry.getReferrer(APP_ID, buyer1), referrer1);
    }

    function test_RevertWhen_SelfReferral() public {
        vm.expectRevert(ReferralRegistry.SelfReferral.selector);
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, buyer1);
    }

    function test_RevertWhen_ZeroReferrer() public {
        vm.expectRevert(ReferralRegistry.ZeroAddress.selector);
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, address(0));
    }

    function test_RevertWhen_UnauthorizedSetReferrer() public {
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(attacker);
        registry.setReferrer(APP_ID, buyer1, referrer1);
    }

    function test_DifferentAppsCanHaveDifferentReferrers() public {
        vm.startPrank(operator);
        registry.setReferrer(1, buyer1, referrer1);
        registry.setReferrer(2, buyer1, referrer2);
        vm.stopPrank();

        assertEq(registry.getReferrer(1, buyer1), referrer1);
        assertEq(registry.getReferrer(2, buyer1), referrer2);
    }

    // =========== Reward Accrual Tests ===========

    function test_AccrueReferralReward() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        uint256 feeAmount = 100 ether;
        uint256 expectedReward = (feeAmount * REFERRAL_BPS) / 10000; // 5 ether

        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, feeAmount);

        assertEq(registry.pendingRewards(referrer1), expectedReward);
    }

    function test_AccrueRewardEmitsEvent() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        uint256 feeAmount = 100 ether;
        uint256 expectedReward = (feeAmount * REFERRAL_BPS) / 10000;

        vm.expectEmit(true, true, true, true);
        emit ReferralRegistry.RewardAccrued(APP_ID, referrer1, buyer1, expectedReward);

        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, feeAmount);
    }

    function test_NoRewardWhenNoReferrer() public {
        // buyer1 has no referrer set
        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, 100 ether);

        // No rewards should be accumulated for anyone
        assertEq(registry.pendingRewards(referrer1), 0);
    }

    function test_MultipleRewardsAccumulate() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        vm.startPrank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, 100 ether);
        registry.accrueReferralReward(APP_ID, buyer1, 200 ether);
        registry.accrueReferralReward(APP_ID, buyer1, 50 ether);
        vm.stopPrank();

        uint256 totalFees = 350 ether;
        uint256 expectedReward = (totalFees * REFERRAL_BPS) / 10000; // 17.5 ether

        assertEq(registry.pendingRewards(referrer1), expectedReward);
    }

    // =========== Claim Tests ===========

    function test_ClaimRewards() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, 100 ether);

        uint256 expectedReward = (100 ether * REFERRAL_BPS) / 10000;
        uint256 balanceBefore = elta.balanceOf(referrer1);

        vm.prank(referrer1);
        registry.claimRewards();

        uint256 balanceAfter = elta.balanceOf(referrer1);
        assertEq(balanceAfter - balanceBefore, expectedReward);
        assertEq(registry.pendingRewards(referrer1), 0);
    }

    function test_ClaimEmitsEvent() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, 100 ether);

        uint256 expectedReward = (100 ether * REFERRAL_BPS) / 10000;

        vm.expectEmit(true, false, false, true);
        emit ReferralRegistry.RewardsClaimed(referrer1, expectedReward);

        vm.prank(referrer1);
        registry.claimRewards();
    }

    function test_ClaimWithNoPending() public {
        // Should not revert, just do nothing
        vm.prank(referrer1);
        registry.claimRewards();

        assertEq(elta.balanceOf(referrer1), 0);
    }

    // =========== Admin Functions Tests ===========

    function test_AdminCanSetReferralBps() public {
        vm.prank(admin);
        registry.setReferralBps(300); // 3%

        assertEq(registry.referralBps(), 300);
    }

    function test_RevertWhen_NonAdminSetsBps() public {
        vm.expectRevert(ReferralRegistry.Unauthorized.selector);
        vm.prank(attacker);
        registry.setReferralBps(300);
    }

    function test_RevertWhen_SetBpsTooHigh() public {
        vm.expectRevert(ReferralRegistry.BpsTooHigh.selector);
        vm.prank(admin);
        registry.setReferralBps(2001);
    }

    function test_AdminCanSetAuthorizedCaller() public {
        address newCaller = makeAddr("newCaller");

        vm.prank(admin);
        registry.setAuthorizedCaller(newCaller, true);

        assertTrue(registry.authorizedCallers(newCaller));
    }

    function test_AdminCanTransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        registry.setAdmin(newAdmin);

        assertEq(registry.admin(), newAdmin);
    }

    // =========== View Functions Tests ===========

    function test_GetReferralCount() public {
        vm.startPrank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);
        registry.setReferrer(APP_ID, buyer2, referrer1);
        vm.stopPrank();

        assertEq(registry.getReferralCount(APP_ID, referrer1), 2);
    }

    function test_GetTotalEarnedByReferrer() public {
        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        vm.startPrank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, 100 ether);
        registry.accrueReferralReward(APP_ID, buyer1, 200 ether);
        vm.stopPrank();

        uint256 expectedTotal = ((100 ether + 200 ether) * REFERRAL_BPS) / 10000;
        assertEq(registry.totalEarned(referrer1), expectedTotal);

        // Claim and verify totalEarned doesn't change
        vm.prank(referrer1);
        registry.claimRewards();

        assertEq(registry.totalEarned(referrer1), expectedTotal);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_ReferralRewardCalculation(uint256 feeAmount) public {
        feeAmount = bound(feeAmount, 1 ether, 1_000_000 ether);

        vm.prank(operator);
        registry.setReferrer(APP_ID, buyer1, referrer1);

        vm.prank(operator);
        registry.accrueReferralReward(APP_ID, buyer1, feeAmount);

        uint256 expectedReward = (feeAmount * REFERRAL_BPS) / 10000;
        assertEq(registry.pendingRewards(referrer1), expectedReward);
    }

    function testFuzz_MultipleBuyersOneReferrer(uint8 numBuyers) public {
        numBuyers = uint8(bound(numBuyers, 1, 10));

        uint256 totalRewards = 0;

        for (uint8 i = 0; i < numBuyers; i++) {
            address buyer = address(uint160(1000 + i));
            uint256 feeAmount = uint256(i + 1) * 10 ether;

            vm.prank(operator);
            registry.setReferrer(APP_ID, buyer, referrer1);

            vm.prank(operator);
            registry.accrueReferralReward(APP_ID, buyer, feeAmount);

            totalRewards += (feeAmount * REFERRAL_BPS) / 10000;
        }

        assertEq(registry.pendingRewards(referrer1), totalRewards);
        assertEq(registry.getReferralCount(APP_ID, referrer1), numBuyers);
    }
}
