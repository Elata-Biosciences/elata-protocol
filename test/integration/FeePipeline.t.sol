// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";

import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";

/**
 * @title FeePipelineTest
 * @notice End-to-end integration tests for the vNext fee pipeline:
 *         BondingCurve/ContentStore/etc -> FeeCollector -> FeeSwapper -> (Treasury + ContributorSplit)
 *
 * Key design invariants:
 * - Protocol-owned fees (FeeKind.LAUNCH_FEE) route 100% to treasury.
 * - App revenue fees route 80/20 (contributors/treasury) unless app is paused.
 * - Sweeps are permissionless (anyone can sweep pending fees).
 */
contract FeePipelineTest is Test {
    uint256 internal constant APP_ID = 1;

    ELTA internal elta;
    AppRegistry internal registry;
    ContributorSplitFactory internal splitFactory;
    FeeSwapper internal feeSwapper;
    FeeCollector internal feeCollector;

    address internal admin = makeAddr("admin");
    address internal governance = makeAddr("governance");
    address internal treasury = makeAddr("treasury");

    address internal ownerSafe = makeAddr("ownerSafe");
    address internal contributor1 = makeAddr("contributor1");

    address internal buyer = makeAddr("buyer");
    address internal sweeper = makeAddr("sweeper");

    address internal split;

    function setUp() public {
        elta = new ELTA(treasury);

        // In tests, make the test contract the "app factory" for registry/splitFactory.
        registry = new AppRegistry(governance, address(this));
        splitFactory = new ContributorSplitFactory(governance, address(this));

        feeSwapper = new FeeSwapper(address(elta), admin, governance, treasury, address(registry));
        feeCollector = new FeeCollector(address(elta), admin, address(feeSwapper), address(feeSwapper));

        // Create per-app contributor split and register app.
        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: contributor1, shares: 10_000});
        split = splitFactory.createSplit(APP_ID, ownerSafe, address(feeSwapper), contributors);

        registry.registerApp(APP_ID, ownerSafe, split, "");

        // Fund buyer (ELTA has fixed supply minted to treasury).
        vm.startPrank(treasury);
        elta.transfer(buyer, 1_000_000 ether);
        vm.stopPrank();

        vm.prank(buyer);
        elta.approve(address(feeCollector), type(uint256).max);
    }

    function test_ProtocolFee_DepositAndSweep_Routes100PercentToTreasury() public {
        uint256 amount = 10_000 ether;

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(split);

        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, FeeKind.LAUNCH_FEE, amount);

        assertEq(feeCollector.pendingEltaFees(APP_ID, FeeKind.LAUNCH_FEE), amount);

        // Sweeps are permissionless.
        vm.prank(sweeper);
        feeCollector.sweepElta(APP_ID, FeeKind.LAUNCH_FEE);

        assertEq(feeCollector.pendingEltaFees(APP_ID, FeeKind.LAUNCH_FEE), 0);
        assertEq(elta.balanceOf(treasury) - treasuryBefore, amount);
        assertEq(elta.balanceOf(split) - splitBefore, 0);
    }

    function test_AppRevenue_DepositAndSweep_SplitsTreasuryAndContributors() public {
        uint256 amount = 10_000 ether;
        uint16 takeBps = feeSwapper.defaultTreasuryTakeBps(); // default 20%

        uint256 expectedTreasury = (amount * uint256(takeBps)) / 10_000;
        uint256 expectedContributors = amount - expectedTreasury;

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(split);

        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, FeeKind.CONTENT_SALE, amount);

        vm.prank(sweeper);
        feeCollector.sweepElta(APP_ID, FeeKind.CONTENT_SALE);

        assertEq(elta.balanceOf(treasury) - treasuryBefore, expectedTreasury);
        assertEq(elta.balanceOf(split) - splitBefore, expectedContributors);

        // ContributorSplit accounting: contributor1 is 100% of shares.
        uint256 releasable = IContributorSplit(split).releasable(address(elta), contributor1);
        assertEq(releasable, expectedContributors);

        uint256 contributorBefore = elta.balanceOf(contributor1);
        IContributorSplit(split).release(address(elta), contributor1);
        assertEq(elta.balanceOf(contributor1) - contributorBefore, expectedContributors);
    }

    function testFuzz_ProtocolFee_SweepConservesAmount(uint256 amount) public {
        // Avoid zero + extreme values that make the test unhelpful.
        amount = (amount % 1_000_000 ether) + 1;

        uint256 treasuryBefore = elta.balanceOf(treasury);

        vm.prank(buyer);
        feeCollector.depositElta(APP_ID, FeeKind.LAUNCH_FEE, amount);

        vm.prank(sweeper);
        feeCollector.sweepElta(APP_ID, FeeKind.LAUNCH_FEE);

        assertEq(elta.balanceOf(treasury) - treasuryBefore, amount);
    }
}

