// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";

/**
 * @title ProtocolConfigSecurity
 * @notice Red team security tests for ProtocolConfig
 */
contract ProtocolConfigSecurity is Test {
    ProtocolConfig public config;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        config = new ProtocolConfig(admin, timelock);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOUNDS BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotExceedMaxBondingCurveTax() public {
        uint256 maxTax = config.MAX_BONDING_CURVE_TAX_BPS();

        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        vm.prank(timelock);
        config.setBondingCurveTradeTaxBps(maxTax + 1);
    }

    function test_Security_CannotExceedMaxTransferTax() public {
        uint256 maxTax = config.MAX_TRANSFER_TAX_BPS();

        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        vm.prank(timelock);
        config.setMaxAppTransferTaxBps(maxTax + 1);
    }

    function test_Security_CannotSetGraduationTargetBelowMin() public {
        uint256 minTarget = config.MIN_GRADUATION_TARGET();

        vm.expectRevert(ProtocolConfig.BelowMinBound.selector);
        vm.prank(timelock);
        config.setGraduationTarget(minTarget - 1);
    }

    function test_Security_CannotSetGraduationTargetAboveMax() public {
        uint256 maxTarget = config.MAX_GRADUATION_TARGET();

        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        vm.prank(timelock);
        config.setGraduationTarget(maxTarget + 1);
    }

    function test_Security_CannotSetLPLockBelowMin() public {
        uint256 minLock = config.MIN_LP_LOCK_DURATION();

        vm.expectRevert(ProtocolConfig.BelowMinBound.selector);
        vm.prank(timelock);
        config.setLpLockDuration(minLock - 1);
    }

    function test_Security_CannotSetLPLockAboveMax() public {
        uint256 maxLock = config.MAX_LP_LOCK_DURATION();

        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        vm.prank(timelock);
        config.setLpLockDuration(maxLock + 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIMELOCK BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyTimelockCanSetBondingCurveTax() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setBondingCurveTradeTaxBps(100);
    }

    function test_Security_OnlyTimelockCanSetTransferTax() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setAppTransferTaxBps(100);
    }

    function test_Security_OnlyTimelockCanSetFeeSplits() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setFeeSplits(2500, 2500, 2500, 2500, 0);
    }

    function test_Security_OnlyTimelockCanSetGraduationTarget() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setGraduationTarget(50000 ether);
    }

    function test_Security_OnlyTimelockCanSetLPLockDuration() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setLpLockDuration(365 days);
    }

    function test_Security_OnlyTimelockCanSetEpochLength() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setEpochLength(2 days);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE SPLIT MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_FeeSplitsMustSumTo100() public {
        vm.expectRevert(ProtocolConfig.InvalidFeeSplits.selector);
        vm.prank(timelock);
        config.setFeeSplits(5000, 5000, 5000, 0, 0); // 150%
    }

    function test_Security_FeeSplitsCannot100PercentToOneBucket() public {
        uint256 maxBucket = config.MAX_BUCKET_BPS();

        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        vm.prank(timelock);
        config.setFeeSplits(maxBucket + 1, 0, 0, 0, 10000 - maxBucket - 1);
    }

    function test_Security_ValidFeeSplitsAccepted() public {
        vm.prank(timelock);
        config.setFeeSplits(3000, 3000, 2000, 1000, 1000); // 30+30+20+10+10 = 100%

        (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury_, uint256 referral) = config.feeSplits();
        assertEq(appStakers + veElta + creator + treasury_ + referral, 10000, "Should sum to 10000");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN ACCESS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyTimelockCanSetTreasury() public {
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(attacker);
        config.setTreasury(attacker);
    }

    function test_Security_OnlyAdminCanSetSlippage() public {
        vm.expectRevert(ProtocolConfig.OnlyAdmin.selector);
        vm.prank(attacker);
        config.setMaxSlippageBps(100);
    }

    function test_Security_CannotSetZeroTreasury() public {
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        vm.prank(timelock);
        config.setTreasury(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EPOCH LENGTH TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotSetEpochBelowMin() public {
        uint256 minEpoch = config.MIN_EPOCH_LENGTH();

        vm.expectRevert(ProtocolConfig.BelowMinBound.selector);
        vm.prank(timelock);
        config.setEpochLength(minEpoch - 1);
    }

    function test_Security_CannotSetEpochAboveMax() public {
        uint256 maxEpoch = config.MAX_EPOCH_LENGTH();

        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        vm.prank(timelock);
        config.setEpochLength(maxEpoch + 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_BondingCurveTaxBound(uint256 tax) public {
        uint256 maxTax = config.MAX_BONDING_CURVE_TAX_BPS();
        tax = bound(tax, 0, maxTax);

        vm.prank(timelock);
        config.setBondingCurveTradeTaxBps(tax);
        assertEq(config.bondingCurveTradeTaxBps(), tax, "Tax should be set");
    }

    function testFuzz_Security_GraduationTargetBound(uint256 target) public {
        uint256 minTarget = config.MIN_GRADUATION_TARGET();
        uint256 maxTarget = config.MAX_GRADUATION_TARGET();
        target = bound(target, minTarget, maxTarget);

        vm.prank(timelock);
        config.setGraduationTarget(target);
        assertEq(config.graduationTarget(), target, "Target should be set");
    }
}
