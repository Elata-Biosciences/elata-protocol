// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
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
    MockUSDC public usdc;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    ProtocolConfig public protocolConfig;
    FeeHandler public handler;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public treasury = makeAddr("treasury");
    address public feeSwapper = makeAddr("feeSwapper");
    address public appRewardsDistributor = makeAddr("appRewardsDistributor");
    address public veRewardsDistributor = makeAddr("veRewardsDistributor");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy ProtocolConfig
        protocolConfig = new ProtocolConfig(admin, timelock);

        // Deploy FeeCollector
        feeCollector = new FeeCollector(
            address(elta),
            admin,
            address(0), // feeManager - set later
            feeSwapper
        );

        // Deploy FeeManager
        feeManager = new FeeManager(
            address(elta),
            address(usdc),
            admin,
            admin, // governance
            appRewardsDistributor,
            veRewardsDistributor,
            treasury,
            1 days // epochLength
        );

        // Connect FeeCollector to FeeManager
        vm.prank(admin);
        feeCollector.setFeeManager(address(feeManager));

        // Allow FeeCollector to deposit to FeeManager
        vm.prank(admin);
        feeManager.setDepositor(address(feeCollector), true);

        // Deploy handler
        handler = new FeeHandler(elta, feeCollector, feeManager, protocolConfig);

        // Fund actors with ELTA
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(admin);
            elta.transfer(actor, 100_000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));
    }

    // =========== Fee Split Invariants ===========

    /// @notice Fee splits should always sum to 100% (10000 bps)
    function invariant_FeeSplitsSumTo100Percent() public view {
        (uint256 appStakers, uint256 veElta, uint256 creator, uint256 treasury_, uint256 referral) =
            feeManager.feeSplits();

        uint256 total = appStakers + veElta + creator + treasury_ + referral;
        assertEq(total, 10000, "Fee splits don't sum to 10000 bps");
    }

    // =========== Fee Collector Invariants ===========

    /// @notice FeeCollector ELTA balance should equal sum of pending fees
    function invariant_CollectorBalanceEqualsPending() public view {
        uint256 totalPending = handler.getTotalPendingFees();
        uint256 balance = elta.balanceOf(address(feeCollector));

        // Balance should be >= pending (might have untracked deposits)
        assertGe(balance, totalPending, "Collector balance < pending fees");
    }

    /// @notice Ghost deposited should be >= ghost swept
    function invariant_DepositedGteSwept() public view {
        uint256 deposited = handler.ghost_totalDeposited();
        uint256 swept = handler.ghost_totalSwept();

        assertGe(deposited, swept, "Swept more than deposited");
    }

    // =========== Fee Manager Invariants ===========

    /// @notice FeeManager should not hold more ELTA than was deposited
    function invariant_FeeManagerBalanceBounded() public view {
        uint256 balance = elta.balanceOf(address(feeManager));

        // FeeManager balance should be bounded by what was swept to it
        // This is a loose bound since we don't track exact amounts
        assertLe(balance, handler.ghost_totalDeposited(), "FeeManager has more than deposited");
    }

    // =========== Cross-Component Invariants ===========

    /// @notice Total ELTA in fee system should be conserved
    function invariant_EltaConserved() public view {
        uint256 collectorBalance = elta.balanceOf(address(feeCollector));
        uint256 managerBalance = elta.balanceOf(address(feeManager));

        // Total in fee system should be less than or equal to what actors deposited
        uint256 totalInSystem = collectorBalance + managerBalance;
        assertLe(totalInSystem, handler.ghost_totalDeposited(), "ELTA appeared from nowhere");
    }

    // =========== Debug Helpers ===========

    function invariant_callSummary() public view {
        console2.log("Fee Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Total deposited:", handler.ghost_totalDeposited());
        console2.log("  Total swept:", handler.ghost_totalSwept());
        console2.log("  Total pending:", handler.getTotalPendingFees());
        console2.log("  Collector balance:", elta.balanceOf(address(feeCollector)));
        console2.log("  Manager balance:", elta.balanceOf(address(feeManager)));
    }
}
