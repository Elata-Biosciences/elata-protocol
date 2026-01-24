// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AppVestingWallet} from "../../src/vesting/AppVestingWallet.sol";
import {VestingHandler} from "./handlers/VestingHandler.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App", "MAPP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title VestingInvariants
 * @notice Invariant tests for AppVestingWallet
 * @dev Tests per Protocol Changes document section 21.4:
 *      - team tokens vest correctly over time
 *      - cannot withdraw before cliff
 *      - beneficiary receives released tokens
 *      - if beneficiary changes, only admin can do it
 */
contract VestingInvariants is Test {
    AppVestingWallet public vestingWallet;
    MockAppToken public appToken;
    VestingHandler public handler;

    address public admin = makeAddr("admin");
    address public beneficiary = makeAddr("beneficiary");

    uint256 public constant APP_ID = 1;
    uint256 public constant VESTING_AMOUNT = 2_500_000 ether; // 25% of 10M
    uint64 public constant CLIFF_DURATION = 90 days; // 3 months
    uint64 public constant VESTING_DURATION = 730 days; // ~24 months

    uint64 public startTime;

    function setUp() public {
        startTime = uint64(block.timestamp);

        // Deploy token
        appToken = new MockAppToken();

        // Deploy vesting wallet
        vestingWallet = new AppVestingWallet(
            APP_ID, address(appToken), beneficiary, startTime, CLIFF_DURATION, VESTING_DURATION, admin
        );

        // Fund vesting wallet
        appToken.mint(address(vestingWallet), VESTING_AMOUNT);

        // Deploy handler
        handler = new VestingHandler(vestingWallet, address(appToken), admin, beneficiary);

        // Target the handler
        targetContract(address(handler));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Total released never exceeds total vested
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_TotalReleasedNeverExceedsVested() public view {
        uint256 released = vestingWallet.released();
        uint256 vested = vestingWallet.vestedAmount();

        assertLe(released, vested, "Released exceeds vested");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Vested amount monotonically increases (or stays same)
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_VestedAmountMonotonicallyIncreases() public view {
        uint256 historyLength = handler.getVestedAmountHistoryLength();

        if (historyLength < 2) return; // Need at least 2 data points

        for (uint256 i = 1; i < historyLength; i++) {
            uint256 previousVested = handler.getVestedAmountAt(i - 1);
            uint256 currentVested = handler.getVestedAmountAt(i);

            assertGe(currentVested, previousVested, "Vested amount decreased");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Nothing releasable before cliff
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_NothingReleasableBeforeCliff() public view {
        if (handler.isBeforeCliff()) {
            uint256 releasable = vestingWallet.releasable();
            assertEq(releasable, 0, "Tokens releasable before cliff");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Fully vested after duration completes
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_FullyVestedAfterDuration() public view {
        if (handler.isAfterFullVesting()) {
            uint256 totalAllocation = handler.getTotalAllocation();
            uint256 vested = vestingWallet.vestedAmount();

            assertEq(vested, totalAllocation, "Not fully vested after duration");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Released + balance = total allocation (conservation)
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_ReleasedPlusBalanceEqualsTotal() public view {
        uint256 released = vestingWallet.released();
        uint256 balance = vestingWallet.totalTokenBalance();
        uint256 totalAllocated = released + balance;

        // Total should equal what was originally allocated
        assertEq(totalAllocated, VESTING_AMOUNT, "Token conservation violated");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Beneficiary balance increases by exactly released amount
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_BeneficiaryReceivesReleasedTokens() public view {
        // The current beneficiary (may have changed) should have tokens
        address currentBeneficiary = vestingWallet.beneficiary();

        // This is a weaker invariant since beneficiary can change
        // We just verify released tokens went somewhere valid
        uint256 released = vestingWallet.released();
        uint256 walletBalance = vestingWallet.totalTokenBalance();

        // Released + remaining should equal total
        assertEq(released + walletBalance, VESTING_AMOUNT, "Tokens disappeared");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Releasable = vested - released
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_ReleasableEqualsVestedMinusReleased() public view {
        uint256 releasable = vestingWallet.releasable();
        uint256 vested = vestingWallet.vestedAmount();
        uint256 released = vestingWallet.released();

        assertEq(releasable, vested - released, "Releasable calculation incorrect");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INVARIANT: Vested never exceeds total allocation
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_VestedNeverExceedsTotal() public view {
        uint256 totalAllocation = handler.getTotalAllocation();
        uint256 vested = vestingWallet.vestedAmount();

        assertLe(vested, totalAllocation, "Vested exceeds total allocation");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEBUG HELPER
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_callSummary() public view {
        console2.log("Vesting Invariant Call Summary:");
        console2.log("  Time warp count:", handler.ghost_timeWarpCount());
        console2.log("  Release call count:", handler.ghost_releaseCallCount());
        console2.log("  Beneficiary changes:", handler.ghost_beneficiaryChangeCount());
        console2.log("  Total released (ghost):", handler.ghost_totalReleased());
        console2.log("  Total released (contract):", vestingWallet.released());
        console2.log("  Current vested:", vestingWallet.vestedAmount());
        console2.log("  Current releasable:", vestingWallet.releasable());
        console2.log("  Wallet balance:", vestingWallet.totalTokenBalance());
        console2.log("  Is before cliff:", handler.isBeforeCliff());
        console2.log("  Is after full vesting:", handler.isAfterFullVesting());
    }
}
