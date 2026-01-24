// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {AppVestingWallet} from "../../../src/vesting/AppVestingWallet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VestingHandler
 * @notice Handler for vesting wallet invariant testing
 * @dev Provides actions for time warping, releasing, and beneficiary changes
 */
contract VestingHandler is CommonBase, StdCheats, StdUtils {
    AppVestingWallet public vestingWallet;
    IERC20 public token;
    address public admin;
    address public beneficiary;

    // Ghost variables for tracking
    uint256 public ghost_totalReleased;
    uint256 public ghost_releaseCallCount;
    uint256 public ghost_timeWarpCount;
    uint256 public ghost_beneficiaryChangeCount;
    uint256 public ghost_lastVestedAmount;
    uint256 public ghost_currentTimestamp;

    // Track vested amounts over time for monotonicity check
    uint256[] public ghost_vestedAmountHistory;

    constructor(AppVestingWallet _vestingWallet, address _token, address _admin, address _beneficiary) {
        vestingWallet = _vestingWallet;
        token = IERC20(_token);
        admin = _admin;
        beneficiary = _beneficiary;
        ghost_currentTimestamp = block.timestamp;
    }

    /**
     * @notice Warp time forward by a bounded amount
     */
    function warpTime(uint256 secondsToWarp) external {
        // Bound to reasonable range: 1 second to 5 years
        secondsToWarp = bound(secondsToWarp, 1, 365 days * 5);

        ghost_currentTimestamp += secondsToWarp;
        vm.warp(ghost_currentTimestamp);
        ghost_timeWarpCount++;

        // Track vested amount after time warp
        uint256 currentVested = vestingWallet.vestedAmount();
        ghost_vestedAmountHistory.push(currentVested);
        ghost_lastVestedAmount = currentVested;
    }

    /**
     * @notice Trigger token release
     */
    function release() external {
        uint256 releasableBefore = vestingWallet.releasable();
        uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiary);

        vestingWallet.release();

        uint256 beneficiaryBalanceAfter = token.balanceOf(beneficiary);
        uint256 actualReleased = beneficiaryBalanceAfter - beneficiaryBalanceBefore;

        ghost_totalReleased += actualReleased;
        ghost_releaseCallCount++;
    }

    /**
     * @notice Change beneficiary (admin only)
     */
    function changeBeneficiary(address newBeneficiary) external {
        // Ensure valid address
        if (newBeneficiary == address(0)) {
            newBeneficiary = makeAddr("newBeneficiary");
        }

        vm.prank(admin);
        try vestingWallet.setBeneficiary(newBeneficiary) {
            beneficiary = newBeneficiary;
            ghost_beneficiaryChangeCount++;
        } catch {}
    }

    /**
     * @notice Multiple release attempts in sequence
     */
    function multipleReleases(uint8 count) external {
        count = uint8(bound(count, 1, 10));

        for (uint8 i = 0; i < count; i++) {
            uint256 beneficiaryBalanceBefore = token.balanceOf(beneficiary);
            vestingWallet.release();
            uint256 actualReleased = token.balanceOf(beneficiary) - beneficiaryBalanceBefore;
            ghost_totalReleased += actualReleased;
            ghost_releaseCallCount++;
        }
    }

    // =========== View Helpers ===========

    function getVestedAmountHistoryLength() external view returns (uint256) {
        return ghost_vestedAmountHistory.length;
    }

    function getVestedAmountAt(uint256 index) external view returns (uint256) {
        require(index < ghost_vestedAmountHistory.length, "Index out of bounds");
        return ghost_vestedAmountHistory[index];
    }

    function getTotalAllocation() external view returns (uint256) {
        return vestingWallet.totalTokenBalance() + vestingWallet.released();
    }

    function isBeforeCliff() external view returns (bool) {
        uint64 start = vestingWallet.start();
        uint64 cliff = vestingWallet.cliff();
        return block.timestamp < start + cliff;
    }

    function isAfterFullVesting() external view returns (bool) {
        return block.timestamp >= vestingWallet.end();
    }
}
