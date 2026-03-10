// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ELTA} from "elta/ELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeKind} from "../../../src/fees/FeeKind.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title FeeHandler
 * @notice Handler for invariant testing of the FeeCollector -> FeeRouterV2 pipeline.
 * @dev Focuses on explicit FeeKind buckets: protocol fees and app revenue.
 */
contract FeeHandler is CommonBase, StdCheats, StdUtils {
    ELTA public elta;
    FeeCollector public feeCollector;

    // Ghost variables for tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalSweptToTreasury;
    uint256 public ghost_totalSweptToSplit;
    uint256 public ghost_callCount;

    // Actor set
    address[] public actors;
    address internal currentActor;

    // App IDs
    uint256 public constant PROTOCOL_APP_ID = 0;
    uint256 public constant APP_ID = 1;

    // Fee kinds used in invariants
    FeeKind public constant PROTOCOL_KIND = FeeKind.LAUNCH_FEE;
    FeeKind public constant APP_KIND = FeeKind.TRADING_FEE;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[actorIndexSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes32) {
        ghost_callCount++;
        _;
    }

    constructor(ELTA _elta, FeeCollector _feeCollector) {
        elta = _elta;
        feeCollector = _feeCollector;

        for (uint256 i; i < 10; ++i) {
            actors.push(address(uint160(0x3000 + i)));
        }
    }

    function depositProtocolElta(uint256 actorSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("depositProtocolElta")
    {
        uint256 balance = elta.balanceOf(currentActor);
        if (balance == 0) return;
        amount = amount % (balance + 1);
        if (amount == 0) return;

        elta.approve(address(feeCollector), amount);
        try feeCollector.depositElta(PROTOCOL_APP_ID, PROTOCOL_KIND, amount) {
            ghost_totalDeposited += amount;
        } catch {}
    }

    function depositAppRevenueElta(uint256 actorSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("depositAppRevenueElta")
    {
        uint256 balance = elta.balanceOf(currentActor);
        if (balance == 0) return;
        amount = amount % (balance + 1);
        if (amount == 0) return;

        elta.approve(address(feeCollector), amount);
        try feeCollector.depositElta(APP_ID, APP_KIND, amount) {
            ghost_totalDeposited += amount;
        } catch {}
    }

    function sweepProtocolElta() external countCall("sweepProtocolElta") {
        uint256 pending = feeCollector.pendingEltaFees(PROTOCOL_APP_ID, PROTOCOL_KIND);
        if (pending == 0) return;

        // Expect: protocol fees are routed 100% to treasury.
        try feeCollector.sweepElta(PROTOCOL_APP_ID, PROTOCOL_KIND) {
            ghost_totalSweptToTreasury += pending;
        } catch {}
    }

    function sweepAppRevenueElta(uint256 takeBps) external countCall("sweepAppRevenueElta") {
        uint256 pending = feeCollector.pendingEltaFees(APP_ID, APP_KIND);
        if (pending == 0) return;

        // takeBps is fixed in FeeSwapper (default 2000), but for ghost accounting we hardcode 20%.
        uint256 treasuryTake = (pending * 2000) / 10_000;
        uint256 splitTake = pending - treasuryTake;

        // Use takeBps seed only to create more handler selectors diversity.
        takeBps = takeBps;

        try feeCollector.sweepElta(APP_ID, APP_KIND) {
            ghost_totalSweptToTreasury += treasuryTake;
            ghost_totalSweptToSplit += splitTake;
        } catch {}
    }

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getTotalPendingElta() external view returns (uint256) {
        return
            feeCollector.pendingEltaFees(PROTOCOL_APP_ID, PROTOCOL_KIND)
                + feeCollector.pendingEltaFees(APP_ID, APP_KIND);
    }
}
