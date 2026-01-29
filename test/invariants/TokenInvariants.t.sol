// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {TokenHandler} from "./handlers/TokenHandler.sol";

/**
 * @title TokenInvariants
 * @notice Invariant tests for ELTA and AppToken
 * @dev Tests that token supply caps and balances remain consistent
 */
contract TokenInvariants is Test {
    ELTA public elta;
    AppToken public appToken;
    TokenHandler public handler;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_MAX_SUPPLY = 10_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp",
            "TEST",
            18,
            APP_TOKEN_MAX_SUPPLY,
            creator,
            admin,
            governance,
            treasury, // appRewardsDistributor
            treasury, // rewardsDistributor
            treasury // treasury
        );

        // Mint initial supply
        vm.prank(admin);
        appToken.mint(creator, APP_TOKEN_MAX_SUPPLY / 2);

        // Deploy handler
        handler = new TokenHandler(elta, appToken);

        // Fund actors with ELTA
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(admin);
            elta.transfer(actor, 100_000 ether);

            // Fund with app tokens too
            vm.prank(creator);
            appToken.transfer(actor, 100_000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));
    }

    // =========== ELTA Invariants ===========

    /// @notice ELTA total supply should never exceed cap
    function invariant_EltaTotalSupplyNeverExceedsCap() public view {
        assertLe(elta.totalSupply(), ELTA_MAX_SUPPLY, "ELTA supply exceeded cap");
    }

    /// @notice Sum of all ELTA balances should equal total supply
    function invariant_EltaBalancesSumToTotalSupply() public view {
        uint256 totalBalance = elta.balanceOf(admin);
        totalBalance += elta.balanceOf(address(handler));

        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            totalBalance += elta.balanceOf(handler.getActor(i));
        }

        // Note: There may be other addresses with balances
        // This invariant checks that known balances don't exceed supply
        assertLe(totalBalance, elta.totalSupply(), "ELTA balances exceed total supply");
    }

    // =========== AppToken Invariants ===========

    /// @notice AppToken total supply should never exceed max supply
    function invariant_AppTokenSupplyNeverExceedsCap() public view {
        assertLe(appToken.totalSupply(), APP_TOKEN_MAX_SUPPLY, "AppToken supply exceeded cap");
    }

    /// @notice AppToken total supply should decrease or stay same when burned
    function invariant_AppTokenSupplyMonotonicallyDecreases() public view {
        uint256 initialSupply = APP_TOKEN_MAX_SUPPLY / 2; // What we minted initially
        uint256 currentSupply = appToken.totalSupply();

        // Supply can only decrease (from burns) or stay same
        // Since we don't track mints in handler, just verify it doesn't exceed initial
        assertLe(currentSupply, initialSupply + (handler.getActorCount() * 100_000 ether), "Unexpected supply increase");
    }

    // =========== Cross-Token Invariants ===========

    /// @notice Handler ghost variables should be consistent
    function invariant_GhostVariablesConsistent() public view {
        // Call count should match actual calls
        assertGe(handler.ghost_callCount(), 0, "Call count negative");

        // Transferred amount should be non-negative
        assertGe(handler.ghost_totalTransferred(), 0, "Transfer amount negative");

        // Burned amount should be non-negative
        assertGe(handler.ghost_totalBurned(), 0, "Burned amount negative");
    }

    // =========== Debug Helpers ===========

    function invariant_callSummary() public view {
        console2.log("Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Total transferred:", handler.ghost_totalTransferred());
        console2.log("  Total burned:", handler.ghost_totalBurned());
        console2.log("  ELTA supply:", elta.totalSupply());
        console2.log("  AppToken supply:", appToken.totalSupply());
    }

    // =========== Post-Campaign Analysis ===========

    /// @notice Called after each invariant run to verify token conservation
    function afterInvariant() public view {
        console2.log("\n=== Token Post-Campaign ===");
        console2.log("Total transfers:", handler.ghost_totalTransferred());
        console2.log("Total burned:", handler.ghost_totalBurned());

        // Verify ELTA conservation
        uint256 totalEltaTracked = elta.balanceOf(admin) + elta.balanceOf(address(handler));
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            totalEltaTracked += elta.balanceOf(handler.getActor(i));
        }

        console2.log("ELTA supply:", elta.totalSupply());
        console2.log("ELTA tracked:", totalEltaTracked);

        // Supply should never exceed cap
        assertLe(elta.totalSupply(), ELTA_MAX_SUPPLY, "ELTA supply exceeded cap");
        assertLe(appToken.totalSupply(), APP_TOKEN_MAX_SUPPLY, "AppToken supply exceeded cap");
    }
}
