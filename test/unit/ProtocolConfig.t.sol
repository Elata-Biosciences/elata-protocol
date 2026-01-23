// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";

/**
 * @title ProtocolConfig Unit Tests
 * @notice TDD tests for ProtocolConfig - all tunable protocol parameters
 * @dev Tests parameter bounds, access control, and events
 */
contract ProtocolConfigTest is Test {
    ProtocolConfig public config;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public user = makeAddr("user");
    address public router1 = makeAddr("router1");
    address public router2 = makeAddr("router2");

    // Events to test
    event AppCreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event AppCreationSeedUpdated(uint256 oldSeed, uint256 newSeed);
    event BondingCurveTaxUpdated(uint256 oldBps, uint256 newBps);
    event GraduationTargetUpdated(uint256 oldTarget, uint256 newTarget);
    event LpLockDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event AppTransferTaxUpdated(uint256 oldBps, uint256 newBps);
    event MaxAppTransferTaxUpdated(uint256 oldMax, uint256 newMax);
    event FeeSplitsUpdated(uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury, uint256 referral);
    event EpochLengthUpdated(uint256 oldLength, uint256 newLength);
    event MaxSlippageUpdated(uint256 oldBps, uint256 newBps);
    event RouterAllowlisted(address indexed router, bool allowed);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    function setUp() public {
        config = new ProtocolConfig(admin, timelock);
    }

    // =========== Deployment Tests ===========

    function test_Deployment() public view {
        assertEq(config.admin(), admin);
        assertEq(config.timelock(), timelock);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        new ProtocolConfig(address(0), timelock);
    }

    function test_RevertWhen_DeployWithZeroTimelock() public {
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        new ProtocolConfig(admin, address(0));
    }

    // =========== Default Values Tests ===========

    function test_DefaultValues() public view {
        // App creation defaults
        assertEq(config.appCreationFeeElta(), 10 ether);
        assertEq(config.appCreationSeedElta(), 100 ether);

        // Bonding curve defaults
        assertEq(config.bondingCurveTradeTaxBps(), 100); // 1%
        assertEq(config.graduationTarget(), 42_000 ether);
        assertEq(config.lpLockDuration(), 365 days * 2);

        // App transfer tax defaults
        assertEq(config.appTransferTaxBps(), 100); // 1%
        assertEq(config.maxAppTransferTaxBps(), 500); // 5% max

        // Fee splits defaults (must sum to 10000)
        (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury, uint256 referral) = config.feeSplits();
        assertEq(appStakers, 7000); // 70%
        assertEq(veElta, 1500); // 15%
        assertEq(creator, 500); // 5%
        assertEq(treasury, 1000); // 10%
        assertEq(referral, 0); // 0%
        assertEq(appStakers + veElta + creator + treasury + referral, 10000);

        // Settlement defaults
        assertEq(config.epochLength(), 1 days);
        assertEq(config.maxSlippageBps(), 500); // 5%
    }

    // =========== Access Control Tests ===========

    function test_OnlyTimelockCanUpdateCriticalParams() public {
        // Critical params should only be changeable via timelock
        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(user);
        config.setFeeSplits(7000, 1500, 500, 1000, 0);

        vm.expectRevert(ProtocolConfig.OnlyTimelock.selector);
        vm.prank(admin);
        config.setFeeSplits(7000, 1500, 500, 1000, 0);

        // But timelock can
        vm.prank(timelock);
        config.setFeeSplits(6000, 2000, 1000, 1000, 0);
    }

    function test_AdminCanUpdateOperationalParams() public {
        // Admin can update operational parameters
        vm.prank(admin);
        config.setMaxSlippageBps(300);
        assertEq(config.maxSlippageBps(), 300);
    }

    function test_OnlyAdminCanUpdateOperationalParams() public {
        vm.expectRevert(ProtocolConfig.OnlyAdmin.selector);
        vm.prank(user);
        config.setMaxSlippageBps(300);
    }

    // =========== App Creation Fee Tests ===========

    function test_SetAppCreationFee() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit AppCreationFeeUpdated(10 ether, 20 ether);
        config.setAppCreationFeeElta(20 ether);
        assertEq(config.appCreationFeeElta(), 20 ether);
    }

    function test_RevertWhen_AppCreationFeeExceedsMax() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setAppCreationFeeElta(1001 ether); // Max is 1000 ether
    }

    // =========== Bonding Curve Tax Tests ===========

    function test_SetBondingCurveTax() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit BondingCurveTaxUpdated(100, 200);
        config.setBondingCurveTradeTaxBps(200);
        assertEq(config.bondingCurveTradeTaxBps(), 200);
    }

    function test_RevertWhen_BondingCurveTaxExceedsMax() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setBondingCurveTradeTaxBps(501); // Max is 500 bps (5%)
    }

    // =========== App Transfer Tax Tests ===========

    function test_SetAppTransferTax() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit AppTransferTaxUpdated(100, 200);
        config.setAppTransferTaxBps(200);
        assertEq(config.appTransferTaxBps(), 200);
    }

    function test_RevertWhen_AppTransferTaxExceedsMax() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setAppTransferTaxBps(501); // Max is 500 bps
    }

    function test_SetMaxAppTransferTax() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit MaxAppTransferTaxUpdated(500, 300);
        config.setMaxAppTransferTaxBps(300);
        assertEq(config.maxAppTransferTaxBps(), 300);
    }

    function test_RevertWhen_MaxTransferTaxBelowCurrentDefault() public {
        // First set default to 200
        vm.prank(timelock);
        config.setAppTransferTaxBps(200);

        // Try to set max below current default
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.InvalidBound.selector);
        config.setMaxAppTransferTaxBps(100);
    }

    // =========== Fee Splits Tests ===========

    function test_SetFeeSplits() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit FeeSplitsUpdated(6000, 2000, 1000, 500, 500);
        config.setFeeSplits(6000, 2000, 1000, 500, 500);

        (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury, uint256 referral) = config.feeSplits();
        assertEq(appStakers, 6000);
        assertEq(veElta, 2000);
        assertEq(creator, 1000);
        assertEq(treasury, 500);
        assertEq(referral, 500);
    }

    function test_RevertWhen_FeeSplitsDontSumTo10000() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.InvalidFeeSplits.selector);
        config.setFeeSplits(6000, 2000, 1000, 500, 600); // Sums to 10100
    }

    function test_RevertWhen_FeeSplitsExceedMaxPerBucket() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setFeeSplits(9500, 100, 100, 100, 200); // appStakers > 90%
    }

    // =========== Graduation Target Tests ===========

    function test_SetGraduationTarget() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit GraduationTargetUpdated(42_000 ether, 50_000 ether);
        config.setGraduationTarget(50_000 ether);
        assertEq(config.graduationTarget(), 50_000 ether);
    }

    function test_RevertWhen_GraduationTargetTooLow() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.BelowMinBound.selector);
        config.setGraduationTarget(999 ether); // Min is 1000 ether
    }

    function test_RevertWhen_GraduationTargetTooHigh() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setGraduationTarget(1_000_001 ether); // Max is 1M ether
    }

    // =========== LP Lock Duration Tests ===========

    function test_SetLpLockDuration() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit LpLockDurationUpdated(365 days * 2, 365 days);
        config.setLpLockDuration(365 days);
        assertEq(config.lpLockDuration(), 365 days);
    }

    function test_RevertWhen_LpLockDurationTooShort() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.BelowMinBound.selector);
        config.setLpLockDuration(29 days); // Min is 30 days
    }

    // =========== Epoch Length Tests ===========

    function test_SetEpochLength() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit EpochLengthUpdated(1 days, 12 hours);
        config.setEpochLength(12 hours);
        assertEq(config.epochLength(), 12 hours);
    }

    function test_RevertWhen_EpochLengthTooShort() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.BelowMinBound.selector);
        config.setEpochLength(59 minutes); // Min is 1 hour
    }

    function test_RevertWhen_EpochLengthTooLong() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setEpochLength(8 days); // Max is 7 days
    }

    // =========== Router Allowlist Tests ===========

    function test_AllowlistRouter() public {
        assertFalse(config.isRouterAllowed(router1));

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RouterAllowlisted(router1, true);
        config.setRouterAllowed(router1, true);

        assertTrue(config.isRouterAllowed(router1));
    }

    function test_RemoveRouterFromAllowlist() public {
        vm.startPrank(admin);
        config.setRouterAllowed(router1, true);
        assertTrue(config.isRouterAllowed(router1));

        vm.expectEmit(true, true, true, true);
        emit RouterAllowlisted(router1, false);
        config.setRouterAllowed(router1, false);
        assertFalse(config.isRouterAllowed(router1));
        vm.stopPrank();
    }

    function test_GetAllAllowedRouters() public {
        vm.startPrank(admin);
        config.setRouterAllowed(router1, true);
        config.setRouterAllowed(router2, true);
        vm.stopPrank();

        address[] memory routers = config.getAllowedRouters();
        assertEq(routers.length, 2);
    }

    // =========== Treasury Tests ===========

    function test_SetTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        address oldTreasury = config.treasury();

        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit TreasuryUpdated(oldTreasury, newTreasury);
        config.setTreasury(newTreasury);

        assertEq(config.treasury(), newTreasury);
    }

    function test_RevertWhen_SetTreasuryToZero() public {
        vm.prank(timelock);
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        config.setTreasury(address(0));
    }

    // =========== Slippage Tests ===========

    function test_SetMaxSlippage() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MaxSlippageUpdated(500, 300);
        config.setMaxSlippageBps(300);
        assertEq(config.maxSlippageBps(), 300);
    }

    function test_RevertWhen_SlippageTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(ProtocolConfig.ExceedsMaxBound.selector);
        config.setMaxSlippageBps(1001); // Max is 1000 bps (10%)
    }

    // =========== Admin Transfer Tests ===========

    function test_TransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        config.transferAdmin(newAdmin);

        assertEq(config.admin(), newAdmin);
    }

    function test_RevertWhen_NonAdminTransfersAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(user);
        vm.expectRevert(ProtocolConfig.OnlyAdmin.selector);
        config.transferAdmin(newAdmin);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_SetFeeSplits(uint256 seed) public {
        // Use seed to generate values that sum to 10000
        // This avoids the vm.assume rejection issue
        seed = bound(seed, 0, type(uint64).max);

        // Generate percentages that sum to 100% (10000 bps)
        uint256 appStakers = (seed % 7001) + 2000; // 2000-9000
        uint256 remaining = 10000 - appStakers;

        uint256 veElta = bound((seed / 7001) % 3001, 0, remaining > 9000 ? 9000 : remaining);
        remaining -= veElta;

        uint256 creator = bound((seed / 21003001) % 2001, 0, remaining > 5000 ? 5000 : remaining);
        remaining -= creator;

        uint256 treasury = bound((seed / 42006002001) % 2001, 0, remaining > 5000 ? 5000 : remaining);
        remaining -= treasury;

        uint256 referral = remaining; // Whatever is left

        // Skip if any bucket exceeds max
        if (appStakers > 9000 || veElta > 9000 || creator > 9000 || treasury > 9000 || referral > 9000) return;

        vm.prank(timelock);
        config.setFeeSplits(appStakers, veElta, creator, treasury, referral);

        (uint256 a, uint256 v, uint256 c, uint256 t, uint256 r) = config.feeSplits();
        assertEq(a, appStakers);
        assertEq(v, veElta);
        assertEq(c, creator);
        assertEq(t, treasury);
        assertEq(r, referral);
    }

    function testFuzz_SetBondingCurveTax(uint256 bps) public {
        bps = bound(bps, 0, 500);

        vm.prank(timelock);
        config.setBondingCurveTradeTaxBps(bps);
        assertEq(config.bondingCurveTradeTaxBps(), bps);
    }
}
