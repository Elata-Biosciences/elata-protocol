// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";
import {FeeHandler} from "./handlers/FeeHandler.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6); // 1B USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @title FeeInvariants
 * @notice Invariant tests for fee pipeline
 * @dev Tests that fee collection and distribution maintain proper accounting
 */
contract FeeInvariants is Test {
    ELTA public elta;
    FeeCollector public feeCollector;
    FeeSwapper public feeRouter;
    AppRegistry public appRegistry;
    ContributorSplitFactory public splitFactory;
    FeeHandler public handler;
    address public contributorSplit;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public feeSwapper = address(0);
    address public ownerSafe = makeAddr("ownerSafe");
    address public contributorA = makeAddr("contributorA");
    address public contributorB = makeAddr("contributorB");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy registry + split factory (appFactory set to this test contract)
        appRegistry = new AppRegistry(admin, address(this));
        splitFactory = new ContributorSplitFactory(admin, address(this));

        // Deploy fee router + collector
        feeRouter = new FeeSwapper(address(elta), admin, admin, treasury, address(appRegistry));
        feeCollector = new FeeCollector(address(elta), admin, address(feeRouter), feeSwapper);

        // Create contributor split and register appId=1
        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](2);
        contributors[0] = IContributorSplit.Contributor({account: contributorA, shares: 60});
        contributors[1] = IContributorSplit.Contributor({account: contributorB, shares: 40});
        contributorSplit = splitFactory.createSplit(1, ownerSafe, address(feeRouter), contributors);
        appRegistry.registerApp(1, ownerSafe, contributorSplit, "");

        // Deploy handler
        handler = new FeeHandler(elta, feeCollector);

        // Fund actors with ELTA
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(admin);
            elta.transfer(actor, 100_000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));
    }

    // =========== Fee Collector Invariants ===========

    /// @notice FeeCollector ELTA balance should equal sum of pending fees
    function invariant_CollectorBalanceEqualsPending() public view {
        uint256 totalPending = handler.getTotalPendingElta();
        uint256 balance = elta.balanceOf(address(feeCollector));

        assertEq(balance, totalPending, "Collector balance != pending fees");
    }

    // =========== Cross-Component Invariants ===========

    /// @notice FeeRouterV2 should not retain ELTA after routing
    function invariant_FeeRouterDoesNotHoldElta() public view {
        assertEq(elta.balanceOf(address(feeRouter)), 0, "FeeRouterV2 retained ELTA");
    }

    /// @notice Total ELTA in fee system should be conserved (no minting in routing)
    function invariant_EltaConserved() public view {
        uint256 collectorBalance = elta.balanceOf(address(feeCollector));
        uint256 treasuryBalance = elta.balanceOf(treasury);
        uint256 splitBalance = elta.balanceOf(contributorSplit);

        uint256 totalInSystem = collectorBalance + treasuryBalance + splitBalance;
        assertEq(totalInSystem, handler.ghost_totalDeposited(), "ELTA not conserved in fee system");
    }

    /// @notice Treasury and split balances match handler ghost routing totals
    function invariant_RoutingMatchesGhostAccounting() public view {
        assertEq(elta.balanceOf(treasury), handler.ghost_totalSweptToTreasury(), "Treasury != ghost");
        assertEq(elta.balanceOf(contributorSplit), handler.ghost_totalSweptToSplit(), "Split != ghost");
    }

    // =========== Debug Helpers ===========

    function invariant_callSummary() public view {
        console2.log("Fee Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Total deposited:", handler.ghost_totalDeposited());
        console2.log("  Treasury swept:", handler.ghost_totalSweptToTreasury());
        console2.log("  Split swept:", handler.ghost_totalSweptToSplit());
        console2.log("  Total pending:", handler.getTotalPendingElta());
        console2.log("  Collector balance:", elta.balanceOf(address(feeCollector)));
        console2.log("  Treasury balance:", elta.balanceOf(treasury));
        console2.log("  Split balance:", elta.balanceOf(contributorSplit));
    }

    // =========== Post-Campaign Analysis ===========

    /// @notice Called after each invariant run to verify fee pipeline integrity
    function afterInvariant() public {
        console2.log("\n=== Fee Pipeline Post-Campaign ===");
        console2.log("Total deposited:", handler.ghost_totalDeposited());
        console2.log("Treasury swept:", handler.ghost_totalSweptToTreasury());
        console2.log("Split swept:", handler.ghost_totalSweptToSplit());

        // Verify all pending fees can be swept
        uint256 pendingFees = handler.getTotalPendingElta();
        uint256 collectorBalance = elta.balanceOf(address(feeCollector));

        console2.log("Pending fees:", pendingFees);
        console2.log("Collector balance:", collectorBalance);

        assertEq(collectorBalance, pendingFees, "Collector balance != pending");
        assertEq(elta.balanceOf(address(feeRouter)), 0, "FeeRouter retained ELTA");
    }
}
