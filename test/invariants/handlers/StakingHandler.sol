// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title StakingHandler
 * @notice Handler for invariant testing of VeELTA staking
 * @dev Performs bounded random operations on staking contract
 */
contract StakingHandler is CommonBase, StdCheats, StdUtils {
    ELTA public elta;
    VeELTA public veElta;

    // Ghost variables for tracking
    uint256 public ghost_totalLocked;
    uint256 public ghost_totalUnlocked;
    uint256 public ghost_lockCount;
    uint256 public ghost_unlockCount;
    uint256 public ghost_extendCount;
    uint256 public ghost_increaseCount;
    uint256 public ghost_callCount;

    // Actors
    address[] public actors;
    address internal currentActor;

    // Track which actors have locks
    mapping(address => bool) public hasLock;

    // Tracking for debugging
    mapping(bytes32 => uint256) public calls;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        ghost_callCount++;
        _;
    }

    constructor(ELTA _elta, VeELTA _veElta) {
        elta = _elta;
        veElta = _veElta;

        // Create actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(address(uint160(0x2000 + i)));
        }
    }

    // =========== Staking Operations ===========

    function lock(uint256 actorSeed, uint256 amount, uint256 durationSeed)
        external
        useActor(actorSeed)
        countCall("lock")
    {
        // Check if actor already has a lock
        (uint128 principal,) = veElta.locks(currentActor);
        if (principal > 0) return;

        // Bound amount to actor's balance
        uint256 balance = elta.balanceOf(currentActor);
        amount = bound(amount, 1 ether, balance);
        if (amount == 0 || balance == 0) return;

        // Bound duration between MIN_LOCK and MAX_LOCK
        uint64 minLock = veElta.MIN_LOCK();
        uint64 maxLock = veElta.MAX_LOCK();
        uint256 duration = bound(durationSeed, minLock, maxLock);
        uint64 unlockTime = uint64(block.timestamp + duration);

        // Approve and lock
        elta.approve(address(veElta), amount);

        try veElta.lock(amount, unlockTime) {
            ghost_totalLocked += amount;
            ghost_lockCount++;
            hasLock[currentActor] = true;
        } catch {}
    }

    function increaseAmount(uint256 actorSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("increaseAmount")
    {
        // Check if actor has a lock
        (uint128 principal, uint64 unlockTime) = veElta.locks(currentActor);
        if (principal == 0 || block.timestamp >= unlockTime) return;

        // Bound amount to actor's balance
        uint256 balance = elta.balanceOf(currentActor);
        amount = bound(amount, 1 ether, balance);
        if (amount == 0 || balance == 0) return;

        // Approve and increase
        elta.approve(address(veElta), amount);

        try veElta.increaseAmount(amount) {
            ghost_totalLocked += amount;
            ghost_increaseCount++;
        } catch {}
    }

    function extendLock(uint256 actorSeed, uint256 extensionSeed) external useActor(actorSeed) countCall("extendLock") {
        // Check if actor has a lock
        (uint128 principal, uint64 unlockTime) = veElta.locks(currentActor);
        if (principal == 0) return;
        if (block.timestamp >= unlockTime) return;

        // Calculate new unlock time
        uint64 maxLock = veElta.MAX_LOCK();
        uint64 maxUnlockTime = uint64(block.timestamp + maxLock);

        // Must extend beyond current unlock time but not exceed max
        if (unlockTime >= maxUnlockTime) return;

        uint64 newUnlockTime = uint64(bound(extensionSeed, unlockTime + 1, maxUnlockTime));

        try veElta.extendLock(newUnlockTime) {
            ghost_extendCount++;
        } catch {}
    }

    function unlock(uint256 actorSeed) external useActor(actorSeed) countCall("unlock") {
        // Check if actor has a lock that's expired
        (uint128 principal, uint64 unlockTime) = veElta.locks(currentActor);
        if (principal == 0) return;
        if (block.timestamp < unlockTime) return;

        try veElta.unlock() {
            ghost_totalUnlocked += principal;
            ghost_unlockCount++;
            hasLock[currentActor] = false;
        } catch {}
    }

    function warpTime(uint256 timeJump) external countCall("warpTime") {
        // Bound time jump to reasonable values (1 hour to 90 days)
        timeJump = bound(timeJump, 1 hours, 90 days);
        vm.warp(block.timestamp + timeJump);
    }

    // =========== View Helpers ===========

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getTotalPrincipalLocked() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint128 principal,) = veElta.locks(actors[i]);
            total += principal;
        }
    }
}
