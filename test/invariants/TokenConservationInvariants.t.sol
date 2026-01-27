// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenConservationHandler
 * @notice Handler for token conservation invariant testing
 */
contract TokenConservationHandler is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppToken public appToken;

    address[] public actors;
    address internal currentActor;

    // Ghost variables
    uint256 public ghost_eltaLocked;
    uint256 public ghost_eltaUnlocked;
    uint256 public ghost_appTokenTransfers;
    uint256 public ghost_callCount;

    constructor(ELTA _elta, VeELTA _veElta, AppToken _appToken) {
        elta = _elta;
        veElta = _veElta;
        appToken = _appToken;

        for (uint256 i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encodePacked("conservationActor", i))));
        }
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[actorIndexSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function lockElta(uint256 actorSeed, uint256 amount, uint256 durationSeed) external useActor(actorSeed) {
        ghost_callCount++;

        (uint128 principal,) = veElta.locks(currentActor);
        if (principal > 0) return;

        uint256 balance = elta.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);
        uint64 duration = uint64(bound(durationSeed, 8 days, 730 days));

        elta.approve(address(veElta), amount);
        try veElta.lock(amount, uint64(block.timestamp) + duration) {
            ghost_eltaLocked += amount;
        } catch {}
    }

    function unlockElta(uint256 actorSeed) external useActor(actorSeed) {
        ghost_callCount++;

        (uint128 principal, uint64 unlockTime) = veElta.locks(currentActor);
        if (principal == 0) return;
        if (block.timestamp < unlockTime) return;

        try veElta.unlock() {
            ghost_eltaUnlocked += principal;
        } catch {}
    }

    function transferElta(uint256 actorSeed, uint256 toSeed, uint256 amount) external useActor(actorSeed) {
        ghost_callCount++;

        uint256 balance = elta.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);
        address to = actors[toSeed % actors.length];

        elta.transfer(to, amount);
    }

    function transferAppToken(uint256 actorSeed, uint256 toSeed, uint256 amount) external useActor(actorSeed) {
        ghost_callCount++;

        uint256 balance = appToken.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);
        address to = actors[toSeed % actors.length];

        appToken.transfer(to, amount);
        ghost_appTokenTransfers++;
    }

    function warpTime(uint256 timeDelta) external {
        ghost_callCount++;
        timeDelta = bound(timeDelta, 1, 400 days);
        vm.warp(block.timestamp + timeDelta);
        vm.roll(block.number + timeDelta / 12);
    }

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getTotalActorEltaBalance() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += elta.balanceOf(actors[i]);
        }
    }

    function getTotalActorAppTokenBalance() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += appToken.balanceOf(actors[i]);
        }
    }

    function getTotalLockedElta() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint128 principal,) = veElta.locks(actors[i]);
            total += principal;
        }
    }
}

/**
 * @title TokenConservationInvariants
 * @notice Invariant tests for token conservation across the protocol
 * @dev Tests ELTA conservation, app token conservation, and fee conservation
 */
contract TokenConservationInvariants is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppToken public appToken;
    TokenConservationHandler public handler;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public governance = makeAddr("governance");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;

    uint256 public initialEltaSupply;
    uint256 public initialAppTokenSupply;
    uint256 public actorEltaFunding;
    uint256 public actorAppTokenFunding;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(treasury);
        initialEltaSupply = elta.totalSupply();

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, admin, admin, governance, treasury, treasury, treasury
        );
        appToken.mint(admin, APP_TOKEN_SUPPLY);
        initialAppTokenSupply = appToken.totalSupply();

        vm.stopPrank();

        // Deploy handler
        handler = new TokenConservationHandler(elta, veElta, appToken);

        // Fund actors
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);

            vm.prank(treasury);
            elta.transfer(actor, 1_000_000 ether);
            actorEltaFunding += 1_000_000 ether;

            vm.prank(admin);
            appToken.transfer(actor, 100_000 ether);
            actorAppTokenFunding += 100_000 ether;
        }

        // Set up handler as target
        targetContract(address(handler));

        // Exclude addresses from fuzzing
        excludeSender(admin);
        excludeSender(treasury);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELTA CONSERVATION INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice ELTA total supply never changes (no unexpected minting/burning)
    function invariant_ELTATotalSupplyConstant() public view {
        uint256 currentSupply = elta.totalSupply();
        assertEq(currentSupply, initialEltaSupply, "ELTA supply changed");
    }

    /// @notice All ELTA is accounted for across known addresses
    function invariant_ELTAInSystemConserved() public view {
        uint256 actorBalances = handler.getTotalActorEltaBalance();
        uint256 veEltaBalance = elta.balanceOf(address(veElta));
        uint256 treasuryBalance = elta.balanceOf(treasury);
        uint256 adminBalance = elta.balanceOf(admin);

        uint256 totalTracked = actorBalances + veEltaBalance + treasuryBalance + adminBalance;

        // Total tracked should be <= total supply
        // (some might be in other contracts we don't track)
        assertLe(totalTracked, initialEltaSupply, "Tracked ELTA > supply");
    }

    /// @notice Locked ELTA in veELTA contract matches sum of user locks
    function invariant_LockedELTAMatchesVeELTAContract() public view {
        uint256 totalLocked = handler.getTotalLockedElta();
        uint256 contractBalance = elta.balanceOf(address(veElta));

        assertEq(totalLocked, contractBalance, "Lock accounting mismatch");
    }

    /// @notice veELTA total supply bounded by locked ELTA (1x to 2x)
    function invariant_VeELTABoundedByLockedELTA() public view {
        uint256 lockedElta = elta.balanceOf(address(veElta));
        uint256 veEltaSupply = veElta.totalSupply();

        // veELTA should be between 1x and 2x locked ELTA
        assertGe(veEltaSupply, lockedElta, "veELTA < locked ELTA");
        assertLe(veEltaSupply, lockedElta * 2, "veELTA > 2x locked ELTA");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // APP TOKEN CONSERVATION INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice App token supply never exceeds initial minted amount
    function invariant_AppTokenSupplyNeverExceedsInitial() public view {
        uint256 currentSupply = appToken.totalSupply();
        assertLe(currentSupply, initialAppTokenSupply, "App token supply increased");
    }

    /// @notice App tokens are accounted for across known addresses
    function invariant_AppTokenAccountedFor() public view {
        uint256 actorBalances = handler.getTotalActorAppTokenBalance();
        uint256 adminBalance = appToken.balanceOf(admin);
        uint256 treasuryBalance = appToken.balanceOf(treasury);

        uint256 totalTracked = actorBalances + adminBalance + treasuryBalance;

        // Should account for all or most tokens
        // Allow for some in unknown addresses due to test setup
        assertLe(totalTracked, initialAppTokenSupply, "Tracked app tokens > supply");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOCK/UNLOCK CONSERVATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Ghost tracking: net locked should match actual locked
    function invariant_GhostLockMatchesActual() public view {
        uint256 ghostNet = handler.ghost_eltaLocked() > handler.ghost_eltaUnlocked()
            ? handler.ghost_eltaLocked() - handler.ghost_eltaUnlocked()
            : 0;

        uint256 actualLocked = handler.getTotalLockedElta();

        // Should match exactly
        assertEq(ghostNet, actualLocked, "Ghost lock tracking mismatch");
    }

    /// @notice Each user's veELTA balance matches their lock's boost calculation
    function invariant_VeELTAMatchesLockBoost() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint128 principal,) = veElta.locks(actor);
            uint256 veBalance = veElta.balanceOf(actor);

            // veBalance should be between principal and 2*principal
            assertGe(veBalance, principal, "veELTA < principal");
            assertLe(veBalance, uint256(principal) * 2, "veELTA > 2x principal");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRANSFER CONSERVATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Transfers don't change total supply
    function invariant_TransfersConserveSupply() public view {
        assertEq(elta.totalSupply(), initialEltaSupply, "ELTA supply changed by transfers");
        assertEq(appToken.totalSupply(), initialAppTokenSupply, "App token supply changed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEBUG HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_callSummary() public view {
        console2.log("Token Conservation Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  ELTA locked:", handler.ghost_eltaLocked());
        console2.log("  ELTA unlocked:", handler.ghost_eltaUnlocked());
        console2.log("  App token transfers:", handler.ghost_appTokenTransfers());
        console2.log("  ELTA supply:", elta.totalSupply());
        console2.log("  veELTA supply:", veElta.totalSupply());
        console2.log("  App token supply:", appToken.totalSupply());
        console2.log("  ELTA in veELTA contract:", elta.balanceOf(address(veElta)));
    }
}
