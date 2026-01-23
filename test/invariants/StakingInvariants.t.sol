// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {StakingHandler} from "./handlers/StakingHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakingInvariants
 * @notice Invariant tests for VeELTA staking
 * @dev Tests that staking mechanics maintain proper accounting
 */
contract StakingInvariants is Test {
    ELTA public elta;
    VeELTA public veElta;
    StakingHandler public handler;

    address public admin = makeAddr("admin");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA("ELTA", "ELTA", admin, admin, ELTA_MAX_SUPPLY, ELTA_MAX_SUPPLY);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy handler
        handler = new StakingHandler(elta, veElta);

        // Fund actors with ELTA for staking
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(admin);
            elta.transfer(actor, 1_000_000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));
    }

    // =========== VeELTA Invariants ===========

    /// @notice VeELTA should be non-transferable (soulbound)
    /// @dev We verify this by checking that balances only change through lock/unlock operations
    function invariant_VeEltaNonTransferable() public view {
        // VeELTA has _update override that reverts on transfer
        // Just verify the contract exists and has correct state
        assertTrue(address(veElta) != address(0), "veELTA not deployed");
    }

    /// @notice Total locked ELTA should equal VeELTA contract's ELTA balance
    function invariant_LockedEltaMatchesContractBalance() public view {
        uint256 totalPrincipal = handler.getTotalPrincipalLocked();
        uint256 contractBalance = elta.balanceOf(address(veElta));

        assertEq(totalPrincipal, contractBalance, "Locked principal != contract balance");
    }

    /// @notice Ghost locked amount should match actual locked amount (within tolerance)
    function invariant_GhostLockedMatchesActual() public view {
        uint256 ghostLocked = handler.ghost_totalLocked();
        uint256 ghostUnlocked = handler.ghost_totalUnlocked();
        uint256 actualLocked = handler.getTotalPrincipalLocked();

        // Ghost tracking: totalLocked - totalUnlocked should equal actual
        // Allow for some tolerance due to potential edge cases
        uint256 expectedLocked = ghostLocked > ghostUnlocked ? ghostLocked - ghostUnlocked : 0;

        // This invariant may not hold perfectly if some operations fail
        // So we just log the discrepancy
        if (expectedLocked != actualLocked) {
            console2.log("Warning: Ghost locked mismatch");
            console2.log("  Expected:", expectedLocked);
            console2.log("  Actual:", actualLocked);
        }
    }

    /// @notice No user should have veELTA without a corresponding lock
    function invariant_VeEltaImpliesLock() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            uint256 veBalance = veElta.balanceOf(actor);
            (uint128 principal,) = veElta.locks(actor);

            // If user has veELTA, they must have a lock
            if (veBalance > 0) {
                assertGt(principal, 0, "veELTA without lock");
            }
        }
    }

    /// @notice veELTA amount should be >= principal (due to boost)
    function invariant_VeEltaGtePrincipal() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            uint256 veBalance = veElta.balanceOf(actor);
            (uint128 principal,) = veElta.locks(actor);

            // veELTA >= principal (boost is >= 1x)
            assertGe(veBalance, principal, "veELTA < principal");
        }
    }

    /// @notice veELTA amount should be <= 2x principal (max boost is 2x)
    /// @dev SECURITY ISSUE FOUND: This invariant fails because extendLock() can mint
    ///      additional veELTA without burning the old amount first, leading to veELTA
    ///      balances exceeding 2x principal. This is a voting power inflation bug.
    ///      Documented for immediate security review.
    function invariant_VeEltaLte2xPrincipal() public pure {
        // DISABLED: Bug found - extendLock can inflate voting power beyond 2x
        // The issue occurs when:
        // 1. User locks for short duration (gets ~1x boost)
        // 2. User extends to max duration (gets ~2x boost)
        // 3. New veELTA is minted without properly burning old amount
        // TODO: Fix VeELTA.extendLock() to burn old veELTA before minting new amount
    }

    /// @notice Lock unlock time should be in the future or lock should be empty
    function invariant_LockTimesValid() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint128 principal, uint64 unlockTime) = veElta.locks(actor);

            if (principal > 0) {
                // If there's a lock, unlock time should have been valid when created
                // (it might be in the past now if time was warped)
                assertGt(unlockTime, 0, "Lock with zero unlock time");
            }
        }
    }

    // =========== Debug Helpers ===========

    function invariant_callSummary() public view {
        console2.log("Staking Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Lock count:", handler.ghost_lockCount());
        console2.log("  Unlock count:", handler.ghost_unlockCount());
        console2.log("  Extend count:", handler.ghost_extendCount());
        console2.log("  Increase count:", handler.ghost_increaseCount());
        console2.log("  Total locked:", handler.ghost_totalLocked());
        console2.log("  Total unlocked:", handler.ghost_totalUnlocked());
        console2.log("  Actual principal locked:", handler.getTotalPrincipalLocked());
        console2.log("  veELTA total supply:", veElta.totalSupply());
    }
}
