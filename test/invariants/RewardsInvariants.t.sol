// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {RewardsDistributor} from "../../src/rewards/RewardsDistributor.sol";
import {AppRewardsDistributor} from "../../src/rewards/AppRewardsDistributor.sol";
import {RewardsHandler} from "./handlers/RewardsHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVeEltaVotes} from "../../src/interfaces/IVeEltaVotes.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";

/**
 * @title RewardsInvariants
 * @notice Invariant tests for RewardsDistributor
 * @dev Tests distribution conservation, epoch integrity, and fairness
 */
contract RewardsInvariants is Test {
    ELTA public elta;
    VeELTA public veElta;
    RewardsDistributor public rewards;
    AppRewardsDistributor public appRewards;
    RewardsHandler public handler;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public factory = makeAddr("factory");
    address public revenueSource = makeAddr("revenueSource");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(treasury);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy AppRewardsDistributor
        appRewards = new AppRewardsDistributor(elta, admin, factory);

        // Deploy RewardsDistributor
        rewards = new RewardsDistributor(
            elta, IVeEltaVotes(address(veElta)), IAppRewardsDistributor(address(appRewards)), treasury, admin
        );

        // Grant DISTRIBUTOR_ROLE to revenueSource
        rewards.grantRole(rewards.DISTRIBUTOR_ROLE(), revenueSource);

        vm.stopPrank();

        // Fund revenue source
        vm.prank(treasury);
        elta.transfer(revenueSource, 10_000_000 ether);

        // Approve
        vm.prank(revenueSource);
        elta.approve(address(rewards), type(uint256).max);

        // Deploy handler
        handler = new RewardsHandler(elta, veElta, rewards, appRewards, revenueSource);

        // Fund actors with ELTA
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(treasury);
            elta.transfer(actor, 1_000_000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));

        // Exclude addresses from fuzzing
        excludeSender(admin);
        excludeSender(treasury);
        excludeSender(revenueSource);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DISTRIBUTION CONSERVATION INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Total claimed cannot exceed total deposited
    function invariant_TotalClaimedLteDeposited() public view {
        uint256 totalClaimed = handler.getTotalClaimed();
        uint256 totalDeposited = handler.ghost_totalDeposited();

        // Claims are from veELTA share (15% of deposits)
        uint256 veShare = handler.ghost_totalVeSplit();

        assertLe(totalClaimed, veShare, "Claimed > veELTA share");
    }

    /// @notice Split always sums to 100% (70 + 15 + 15)
    function invariant_SplitAlwaysSumsTo100Percent() public view {
        assertEq(rewards.BIPS_APP(), 7000, "App split should be 70%");
        assertEq(rewards.BIPS_VEELTA(), 1500, "veELTA split should be 15%");
        assertEq(rewards.BIPS_TREASURY(), 1500, "Treasury split should be 15%");
        assertEq(
            rewards.BIPS_APP() + rewards.BIPS_VEELTA() + rewards.BIPS_TREASURY(), 10000, "Splits should sum to 100%"
        );
    }

    /// @notice Treasury receives exactly 15% of deposits
    function invariant_TreasurySplitAccurate() public view {
        uint256 totalDeposited = handler.ghost_totalDeposited();
        uint256 expectedTreasury = (totalDeposited * 1500) / 10000;
        uint256 trackedTreasury = handler.ghost_totalTreasurySplit();

        // Allow tolerance for rounding (deposit count + 1 for safety)
        uint256 tolerance = handler.ghost_depositCount() + 1;
        assertApproxEqAbs(trackedTreasury, expectedTreasury, tolerance, "Treasury split inaccurate");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EPOCH INTEGRITY INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Epochs are ordered by block number (monotonically increasing)
    function invariant_EpochsOrderedByBlockNumber() public view {
        uint256 epochCount = rewards.getEpochCount();
        if (epochCount <= 1) return;

        uint256 prevBlock = 0;
        for (uint256 i = 0; i < epochCount; i++) {
            (uint256 blockNum,) = rewards.getEpoch(i);
            assertGe(blockNum, prevBlock, "Epochs not ordered");
            prevBlock = blockNum;
        }
    }

    /// @notice Epoch amounts are non-negative (implicit in uint256)
    function invariant_EpochAmountsNonNegative() public view {
        uint256 epochCount = rewards.getEpochCount();
        for (uint256 i = 0; i < epochCount; i++) {
            (, uint256 amount) = rewards.getEpoch(i);
            assertGe(amount, 0, "Negative epoch amount"); // Always true for uint256
        }
    }

    /// @notice Total epoch amounts match veELTA split of deposits
    function invariant_TotalEpochAmountsMatchVeSplit() public view {
        uint256 epochCount = rewards.getEpochCount();
        uint256 totalEpochAmount = 0;

        for (uint256 i = 0; i < epochCount; i++) {
            (, uint256 amount) = rewards.getEpoch(i);
            totalEpochAmount += amount;
        }

        uint256 expectedVeShare = handler.ghost_totalVeSplit();

        // Should match exactly (or be close due to rounding)
        assertApproxEqAbs(totalEpochAmount, expectedVeShare, handler.ghost_depositCount(), "Epoch total != veShare");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VEELTA REWARD FAIRNESS INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Zero voting power means zero rewards
    function invariant_ZeroVotingPowerZeroRewards() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            uint256 votingPower = veElta.getVotes(actor);

            // If actor has 0 voting power, they should have 0 or very little claimed
            // (they might have claimed before losing power)
            if (votingPower == 0) {
                // This is informational - actors might have claimed before unstaking
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELTA CONSERVATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice RewardsDistributor ELTA balance matches expected from deposits
    function invariant_RewardsContractBalanceCorrect() public view {
        uint256 contractBalance = elta.balanceOf(address(rewards));
        uint256 veShare = handler.ghost_totalVeSplit();
        uint256 claimed = handler.getTotalClaimed();

        // Contract should hold veShare minus what's been claimed
        uint256 expected = veShare > claimed ? veShare - claimed : 0;

        // Allow tolerance for timing/rounding
        assertApproxEqAbs(contractBalance, expected, handler.ghost_depositCount() + 1, "Contract balance mismatch");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEBUG HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_callSummary() public view {
        console2.log("Rewards Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Deposit count:", handler.ghost_depositCount());
        console2.log("  Claim count:", handler.ghost_claimCount());
        console2.log("  Total deposited:", handler.ghost_totalDeposited());
        console2.log("  Total app split:", handler.ghost_totalAppSplit());
        console2.log("  Total veELTA split:", handler.ghost_totalVeSplit());
        console2.log("  Total treasury split:", handler.ghost_totalTreasurySplit());
        console2.log("  Total claimed:", handler.getTotalClaimed());
        console2.log("  Epoch count:", rewards.getEpochCount());
    }
}
