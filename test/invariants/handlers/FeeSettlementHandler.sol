// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {FeeKind} from "../../../src/fees/FeeKind.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FeeSettlementHandler
 * @notice Handler for fee settlement invariant testing
 * @dev Tests per Protocol Changes 21.1:
 *      - Any taxed app token received by FeeCollector can be swept into ELTA
 *      - Daily settlement cannot be called twice for the same app within epoch
 *      - TreasuryUSDCVault receives USDC; not app tokens
 *      - Caller incentive never exceeds cap; only paid when settlement occurs
 */
contract FeeSettlementHandler is CommonBase, StdCheats, StdUtils {
    ELTA public elta;
    FeeCollector public feeCollector;
    FeeManager public feeManager;

    // Test actors
    address[] public actors;
    uint256[] public appIds;

    // Ghost variables
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalSwept;
    uint256 public ghost_epochCloseAttempts;
    uint256 public ghost_successfulEpochCloses;
    uint256 public ghost_failedEpochCloses;
    uint256 public ghost_callCount;

    // Track deposits per app
    mapping(uint256 => uint256) public ghost_depositsPerApp;
    mapping(uint256 => uint256) public ghost_sweepsPerApp;
    mapping(uint256 => uint256) public ghost_lastEpochCloseTime;

    // Track caller incentives
    uint256 public ghost_totalIncentivesPaid;
    uint256 public ghost_maxIncentivePaid;

    constructor(ELTA _elta, FeeCollector _feeCollector, FeeManager _feeManager) {
        elta = _elta;
        feeCollector = _feeCollector;
        feeManager = _feeManager;

        // Create test actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("feeActor", i)));
            actors.push(actor);
        }

        // Create app IDs
        for (uint256 i = 0; i < 3; i++) {
            appIds.push(i);
        }
    }

    // =========== Deposit Actions ===========

    /**
     * @notice Deposit ELTA fees for an app
     */
    function depositElta(uint256 actorIndex, uint256 appIndex, uint256 amount) external {
        actorIndex = bound(actorIndex, 0, actors.length - 1);
        appIndex = bound(appIndex, 0, appIds.length - 1);

        address actor = actors[actorIndex];
        uint256 appId = appIds[appIndex];

        uint256 actorBalance = elta.balanceOf(actor);
        if (actorBalance == 0) return;

        amount = bound(amount, 1 ether, actorBalance);

        vm.startPrank(actor);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(appId, amount);
        vm.stopPrank();

        ghost_totalDeposited += amount;
        ghost_depositsPerApp[appId] += amount;
        ghost_callCount++;
    }

    /**
     * @notice Sweep ELTA from FeeCollector to FeeManager
     */
    function sweepElta(uint256 appIndex) external {
        appIndex = bound(appIndex, 0, appIds.length - 1);
        uint256 appId = appIds[appIndex];

        uint256 pending = feeCollector.pendingEltaFees(appId, FeeKind.TRADING_FEE);
        if (pending == 0) return;

        feeCollector.sweepElta(appId);

        ghost_totalSwept += pending;
        ghost_sweepsPerApp[appId] += pending;
        ghost_callCount++;
    }

    // =========== Epoch Actions ===========

    /**
     * @notice Attempt to close epoch for an app
     */
    function closeEpoch(uint256 appIndex) external {
        appIndex = bound(appIndex, 0, appIds.length - 1);
        uint256 appId = appIds[appIndex];

        ghost_epochCloseAttempts++;

        try feeManager.closeEpoch(appId) {
            ghost_successfulEpochCloses++;
            ghost_lastEpochCloseTime[appId] = block.timestamp;
        } catch {
            ghost_failedEpochCloses++;
        }

        ghost_callCount++;
    }

    /**
     * @notice Warp time forward
     */
    function warpTime(uint256 secondsToWarp) external {
        // Bound to reasonable range: 1 hour to 3 days
        secondsToWarp = bound(secondsToWarp, 1 hours, 3 days);
        vm.warp(block.timestamp + secondsToWarp);
        ghost_callCount++;
    }

    // =========== View Helpers ===========

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        require(index < actors.length, "Index out of bounds");
        return actors[index];
    }

    function getAppCount() external view returns (uint256) {
        return appIds.length;
    }

    function getAppId(uint256 index) external view returns (uint256) {
        require(index < appIds.length, "Index out of bounds");
        return appIds[index];
    }

    function getTotalPendingFees() external view returns (uint256 total) {
        for (uint256 i = 0; i < appIds.length; i++) {
            total += feeCollector.pendingEltaFees(appIds[i], FeeKind.TRADING_FEE);
        }
    }

    function getTotalPendingToDistribute() external view returns (uint256 total) {
        for (uint256 i = 0; i < appIds.length; i++) {
            total += feeManager.pendingEltaToDistribute(appIds[i]);
        }
    }

    function canCloseAnyEpoch() external view returns (bool) {
        for (uint256 i = 0; i < appIds.length; i++) {
            if (feeManager.canCloseEpoch(appIds[i])) {
                return true;
            }
        }
        return false;
    }
}
