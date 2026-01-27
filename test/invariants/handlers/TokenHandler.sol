// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

/**
 * @title TokenHandler
 * @notice Handler for invariant testing of ELTA and AppToken
 * @dev Performs bounded random operations on tokens
 */
contract TokenHandler is CommonBase, StdCheats, StdUtils {
    ELTA public elta;
    AppToken public appToken;

    // Ghost variables for tracking
    uint256 public ghost_totalMinted;
    uint256 public ghost_totalBurned;
    uint256 public ghost_totalTransferred;
    uint256 public ghost_callCount;

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

    constructor(ELTA _elta, AppToken _appToken) {
        elta = _elta;
        appToken = _appToken;

        // Create actors
        for (uint256 i = 0; i < 10; i++) {
            actors.push(address(uint160(0x1000 + i)));
        }
    }

    // =========== ELTA Operations ===========

    function elta_transfer(uint256 actorSeed, uint256 toSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("elta_transfer")
    {
        address to = actors[bound(toSeed, 0, actors.length - 1)];
        amount = bound(amount, 0, elta.balanceOf(currentActor));

        if (amount > 0 && to != address(0)) {
            elta.transfer(to, amount);
            ghost_totalTransferred += amount;
        }
    }

    function elta_approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("elta_approve")
    {
        address spender = actors[bound(spenderSeed, 0, actors.length - 1)];
        amount = bound(amount, 0, type(uint256).max);

        elta.approve(spender, amount);
    }

    function elta_transferFrom(uint256 actorSeed, uint256 fromSeed, uint256 toSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("elta_transferFrom")
    {
        address from = actors[bound(fromSeed, 0, actors.length - 1)];
        address to = actors[bound(toSeed, 0, actors.length - 1)];

        uint256 allowance = elta.allowance(from, currentActor);
        uint256 balance = elta.balanceOf(from);
        amount = bound(amount, 0, allowance < balance ? allowance : balance);

        if (amount > 0 && to != address(0)) {
            elta.transferFrom(from, to, amount);
            ghost_totalTransferred += amount;
        }
    }

    // =========== AppToken Operations ===========

    function appToken_transfer(uint256 actorSeed, uint256 toSeed, uint256 amount)
        external
        useActor(actorSeed)
        countCall("appToken_transfer")
    {
        address to = actors[bound(toSeed, 0, actors.length - 1)];
        amount = bound(amount, 0, appToken.balanceOf(currentActor));

        if (amount > 0 && to != address(0)) {
            appToken.transfer(to, amount);
            ghost_totalTransferred += amount;
        }
    }

    function appToken_burn(uint256 actorSeed, uint256 amount) external useActor(actorSeed) countCall("appToken_burn") {
        amount = bound(amount, 0, appToken.balanceOf(currentActor));

        if (amount > 0) {
            appToken.burn(amount);
            ghost_totalBurned += amount;
        }
    }

    // =========== View Helpers ===========

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function forEachActor(function(address) external func) external {
        for (uint256 i = 0; i < actors.length; i++) {
            func(actors[i]);
        }
    }

    function reduceActors(uint256 acc, function(uint256, address) external returns (uint256) func)
        external
        returns (uint256)
    {
        for (uint256 i = 0; i < actors.length; i++) {
            acc = func(acc, actors[i]);
        }
        return acc;
    }
}
