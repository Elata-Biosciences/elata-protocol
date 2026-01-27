// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {ProtocolConfig} from "../../../src/core/ProtocolConfig.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title FeeHandler
 * @notice Handler for invariant testing of fee pipeline
 * @dev Performs bounded random operations on FeeCollector and FeeManager
 */
contract FeeHandler is CommonBase, StdCheats, StdUtils {
    ELTA public elta;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    ProtocolConfig public protocolConfig;

    // Ghost variables for tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalSwept;
    uint256 public ghost_totalDistributed;
    uint256 public ghost_callCount;

    // App IDs to test with
    uint256[] public appIds;

    // Actors
    address[] public actors;
    address internal currentActor;

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

    constructor(ELTA _elta, FeeCollector _feeCollector, FeeManager _feeManager, ProtocolConfig _protocolConfig) {
        elta = _elta;
        feeCollector = _feeCollector;
        feeManager = _feeManager;
        protocolConfig = _protocolConfig;

        // Create actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(address(uint160(0x3000 + i)));
        }

        // Create app IDs to test
        for (uint256 i = 0; i < 5; i++) {
            appIds.push(i);
        }
    }

    // =========== FeeCollector Operations ===========

    function depositElta(uint256 actorSeed, uint256 appIdSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("depositElta")
    {
        uint256 appId = appIds[bound(appIdSeed, 0, appIds.length - 1)];

        // Bound amount to actor's balance
        uint256 balance = elta.balanceOf(currentActor);
        amount = bound(amount, 0, balance);
        if (amount == 0) return;

        // Approve and deposit
        elta.approve(address(feeCollector), amount);

        try feeCollector.depositElta(appId, amount) {
            ghost_totalDeposited += amount;
        } catch {}
    }

    function sweepElta(uint256 appIdSeed) external countCall("sweepElta") {
        uint256 appId = appIds[bound(appIdSeed, 0, appIds.length - 1)];

        uint256 pending = feeCollector.pendingEltaFees(appId);
        if (pending == 0) return;

        try feeCollector.sweepElta(appId) {
            ghost_totalSwept += pending;
        } catch {}
    }

    // =========== FeeManager Operations ===========

    function closeEpoch(uint256 appIdSeed) external countCall("closeEpoch") {
        uint256 appId = appIds[bound(appIdSeed, 0, appIds.length - 1)];

        try feeManager.closeEpoch(appId) {
            // Track distributed amount (hard to track precisely without events)
            ghost_totalDistributed++;
        } catch {}
    }

    function warpTime(uint256 timeJump) external countCall("warpTime") {
        // Bound time jump to reasonable values (1 hour to 7 days)
        timeJump = bound(timeJump, 1 hours, 7 days);
        vm.warp(block.timestamp + timeJump);
    }

    // =========== View Helpers ===========

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getAppIdCount() external view returns (uint256) {
        return appIds.length;
    }

    function getTotalPendingFees() external view returns (uint256 total) {
        for (uint256 i = 0; i < appIds.length; i++) {
            total += feeCollector.pendingEltaFees(appIds[i]);
        }
    }
}
