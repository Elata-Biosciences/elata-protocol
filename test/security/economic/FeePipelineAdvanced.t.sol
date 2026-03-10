// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeSwapper} from "../../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../../src/registry/AppRegistry.sol";
import {ContributorSplit} from "../../../src/contributors/ContributorSplit.sol";
import {IContributorSplit} from "../../../src/interfaces/IContributorSplit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Focused advanced tests for the v2 fee pipeline: FeeCollector -> FeeSwapper -> Treasury
contract FeePipelineAdvanced is Test {
    ELTA elta;
    FeeCollector feeCollector;
    FeeSwapper feeSwapper;
    AppRegistry appRegistry;
    ContributorSplit split1;
    ContributorSplit split2;

    address admin = makeAddr("admin");
    address governance = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address user = makeAddr("user");

    function setUp() public {
        vm.prank(admin);
        elta = new ELTA(admin);

        appRegistry = new AppRegistry(governance, address(this));
        feeSwapper = new FeeSwapper(address(elta), admin, governance, treasury, address(appRegistry));

        // FeeCollector uses feeRouter for ELTA sweeps and feeSwapper for token sweeps.
        // In the unified model, both point to the same FeeSwapper contract.
        feeCollector = new FeeCollector(address(elta), admin, address(feeSwapper), address(feeSwapper));

        // Register a couple of apps so app-revenue FeeKinds can route to contributor splits.
        // ContributorSplit must be an actual contract since FeeSwapper makes a typed external call.
        split1 = new ContributorSplit();
        split2 = new ContributorSplit();
        IContributorSplit.Contributor[] memory noContributors = new IContributorSplit.Contributor[](0);
        split1.initialize(1, makeAddr("owner1"), address(feeSwapper), 1, noContributors);
        split2.initialize(2, makeAddr("owner2"), address(feeSwapper), 1, noContributors);
        appRegistry.registerApp(1, split1.ownerSafe(), address(split1), "ipfs://meta1");
        appRegistry.registerApp(2, split2.ownerSafe(), address(split2), "ipfs://meta2");

        vm.prank(admin);
        elta.transfer(user, 1_000_000 ether);
    }

    function test_DepositTrackingByAppAndKind() public {
        vm.startPrank(user);
        elta.approve(address(feeCollector), 300 ether);
        feeCollector.depositElta(1, FeeKind.TRADING_FEE, 100 ether);
        feeCollector.depositElta(2, FeeKind.TRADING_FEE, 200 ether);
        vm.stopPrank();

        assertEq(feeCollector.pendingEltaFees(1, FeeKind.TRADING_FEE), 100 ether);
        assertEq(feeCollector.pendingEltaFees(2, FeeKind.TRADING_FEE), 200 ether);
    }

    function test_SweepRoutesToTreasury() public {
        vm.startPrank(user);
        elta.approve(address(feeCollector), 100 ether);
        feeCollector.depositElta(1, FeeKind.TRADING_FEE, 100 ether);
        vm.stopPrank();

        uint256 beforeTreasury = elta.balanceOf(treasury);
        uint256 beforeSplit = elta.balanceOf(address(split1));

        feeCollector.sweepElta(1, FeeKind.TRADING_FEE);
        uint256 afterTreasury = elta.balanceOf(treasury);
        uint256 afterSplit = elta.balanceOf(address(split1));

        // Trading fees are app revenue and must route 80/20 (contributors/treasury).
        assertEq(afterTreasury - beforeTreasury, 20 ether);
        assertEq(afterSplit - beforeSplit, 80 ether);
        assertEq(feeCollector.pendingEltaFees(1, FeeKind.TRADING_FEE), 0);
    }
}

