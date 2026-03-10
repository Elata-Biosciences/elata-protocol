// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppBondingCurve} from "../../../src/apps/AppBondingCurve.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title BondingCurveHandler
 * @notice Handler for invariant testing of AppBondingCurve
 * @dev Performs bounded random operations on bonding curves
 */
contract BondingCurveHandler is CommonBase, StdCheats, StdUtils {
    ELTA public elta;
    AppBondingCurve public curve;
    AppToken public appToken;

    // Ghost variables for tracking
    uint256 public ghost_totalBought;
    uint256 public ghost_totalSpent;
    uint256 public ghost_buyCount;
    uint256 public ghost_callCount;

    // Track constant product for invariant checking
    uint256 public initialK;
    bool public kInitialized;

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

    constructor(ELTA _elta, AppBondingCurve _curve, AppToken _appToken) {
        elta = _elta;
        curve = _curve;
        appToken = _appToken;

        // Create actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(address(uint160(0x4000 + i)));
        }
    }

    // =========== Bonding Curve Operations ===========

    function buy(uint256 actorSeed, uint256 amount, uint256 maxSpend) external useActor(actorSeed) countCall("buy") {
        // Skip if curve is not active
        AppBondingCurve.CurveState state = curve.state();
        if (state != AppBondingCurve.CurveState.ACTIVE) return;

        // Record initial K if not set
        if (!kInitialized) {
            initialK = curve.reserveElta() * curve.reserveToken();
            kInitialized = true;
        }

        // Bound amount to actor's balance and reasonable range
        uint256 balance = elta.balanceOf(currentActor);
        amount = bound(amount, 0.01 ether, balance);
        if (amount == 0 || balance == 0) return;

        // Set reasonable max spend
        maxSpend = bound(maxSpend, amount, amount * 2);

        // Approve and buy
        elta.approve(address(curve), maxSpend);

        uint256 eltaBefore = elta.balanceOf(currentActor);
        uint256 tokenBefore = appToken.balanceOf(currentActor);

        try curve.buy(amount, maxSpend, address(0)) {
            uint256 eltaSpent = eltaBefore - elta.balanceOf(currentActor);
            uint256 tokensReceived = appToken.balanceOf(currentActor) - tokenBefore;

            ghost_totalSpent += eltaSpent;
            ghost_totalBought += tokensReceived;
            ghost_buyCount++;
        } catch {}
    }

    function activate() external countCall("activate") {
        // Only callable by governance
        address governance = curve.governance();
        vm.prank(governance);

        try curve.activate() {} catch {}
    }

    function warpTime(uint256 timeJump) external countCall("warpTime") {
        // Bound time jump to reasonable values (1 minute to 30 days)
        timeJump = bound(timeJump, 1 minutes, 30 days);
        vm.warp(block.timestamp + timeJump);
    }

    // =========== View Helpers ===========

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getCurrentK() external view returns (uint256) {
        return curve.reserveElta() * curve.reserveToken();
    }

    function getInitialK() external view returns (uint256) {
        return initialK;
    }

    function isKInitialized() external view returns (bool) {
        return kInitialized;
    }

    function getCurveState() external view returns (AppBondingCurve.CurveState) {
        return curve.state();
    }

    function getReserveElta() external view returns (uint256) {
        return curve.reserveElta();
    }

    function getTargetRaised() external view returns (uint256) {
        return curve.targetRaisedElta();
    }

    function isGraduated() external view returns (bool) {
        return curve.graduated();
    }
}
