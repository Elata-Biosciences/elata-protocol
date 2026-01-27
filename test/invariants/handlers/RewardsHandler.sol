// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {RewardsDistributor} from "../../../src/rewards/RewardsDistributor.sol";
import {AppRewardsDistributor} from "../../../src/rewards/AppRewardsDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RewardsHandler
 * @notice Handler contract for rewards distribution invariant testing
 * @dev Exposes reward actions with ghost variable tracking
 */
contract RewardsHandler is Test {
    ELTA public elta;
    VeELTA public veElta;
    RewardsDistributor public rewards;
    AppRewardsDistributor public appRewards;

    // Actors
    address[] public actors;
    address internal currentActor;

    // Revenue source (has DISTRIBUTOR_ROLE)
    address public revenueSource;

    // Ghost variables
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalTreasurySplit;
    uint256 public ghost_totalVeSplit;
    uint256 public ghost_totalAppSplit;
    uint256 public ghost_depositCount;
    uint256 public ghost_claimCount;
    uint256 public ghost_callCount;

    // Track claims
    mapping(address => uint256) public totalClaimed;

    constructor(
        ELTA _elta,
        VeELTA _veElta,
        RewardsDistributor _rewards,
        AppRewardsDistributor _appRewards,
        address _revenueSource
    ) {
        elta = _elta;
        veElta = _veElta;
        rewards = _rewards;
        appRewards = _appRewards;
        revenueSource = _revenueSource;

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encodePacked("rewardActor", i))));
        }
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[actorIndexSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function deposit(uint256 amount) external {
        ghost_callCount++;

        // Bound amount
        uint256 balance = elta.balanceOf(revenueSource);
        if (balance == 0) return;

        amount = bound(amount, 1 ether, balance / 2);

        vm.startPrank(revenueSource);
        elta.approve(address(rewards), amount);

        try rewards.deposit(amount) {
            ghost_totalDeposited += amount;
            ghost_depositCount++;

            // Track splits (70/15/15)
            uint256 appShare = (amount * 7000) / 10000;
            uint256 veShare = (amount * 1500) / 10000;
            uint256 treasuryShare = (amount * 1500) / 10000;

            ghost_totalAppSplit += appShare;
            ghost_totalVeSplit += veShare;
            ghost_totalTreasurySplit += treasuryShare;
        } catch {
            // Deposit failed
        }
        vm.stopPrank();
    }

    function createLock(uint256 actorSeed, uint256 amount, uint256 durationSeed) external useActor(actorSeed) {
        ghost_callCount++;

        // Skip if actor already has a lock
        (uint128 principal,) = veElta.locks(currentActor);
        if (principal > 0) return;

        // Bound amount
        uint256 balance = elta.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1 ether, balance);

        // Bound duration
        uint64 duration = uint64(bound(durationSeed, 8 days, 730 days));
        uint64 unlockTime = uint64(block.timestamp) + duration;

        elta.approve(address(veElta), amount);
        try veElta.lock(amount, unlockTime) {
        // Lock succeeded
        }
            catch {
            // Lock failed
        }
    }

    function claimVeRewards(uint256 actorSeed, uint256 fromEpochSeed, uint256 toEpochSeed)
        external
        useActor(actorSeed)
    {
        ghost_callCount++;

        uint256 epochCount = rewards.getEpochCount();
        if (epochCount == 0) return;

        uint256 fromEpoch = fromEpochSeed % epochCount;
        uint256 toEpoch = toEpochSeed % epochCount;
        if (fromEpoch > toEpoch) {
            (fromEpoch, toEpoch) = (toEpoch, fromEpoch);
        }

        // Check if actor has voting power
        uint256 votes = veElta.getVotes(currentActor);
        if (votes == 0) return;

        // Need to roll forward for snapshot
        vm.roll(block.number + 1);

        uint256 balanceBefore = elta.balanceOf(currentActor);
        try rewards.claimVe(fromEpoch, toEpoch) {
            uint256 balanceAfter = elta.balanceOf(currentActor);
            uint256 claimed = balanceAfter - balanceBefore;
            totalClaimed[currentActor] += claimed;
            ghost_claimCount++;
        } catch {
            // Claim failed
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    function warpTime(uint256 timeDelta) external {
        ghost_callCount++;
        timeDelta = bound(timeDelta, 1, 7 days);
        vm.warp(block.timestamp + timeDelta);
        vm.roll(block.number + timeDelta / 12);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getTotalClaimed() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += totalClaimed[actors[i]];
        }
    }

    function getTotalVotingPower() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += veElta.getVotes(actors[i]);
        }
    }
}
