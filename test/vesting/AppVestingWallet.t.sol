// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AppVestingWallet} from "../../src/vesting/AppVestingWallet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App", "MAPP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title AppVestingWalletTest
 * @notice Unit tests for AppVestingWallet contract
 * @dev Tests vesting schedule, cliff, release, and beneficiary management
 *
 * Per Protocol Changes document section 11:
 * - Team allocation held in OZ-style vesting wallet from app creation (T0)
 * - Default: 3 month cliff, 24 month linear vest after cliff
 * - Beneficiary is the team multisig
 * - Optional: ability to update beneficiary only via admin
 */
contract AppVestingWalletTest is Test {
    AppVestingWallet public vestingWallet;
    MockAppToken public appToken;

    address public admin = makeAddr("admin");
    address public beneficiary = makeAddr("beneficiary");
    address public newBeneficiary = makeAddr("newBeneficiary");
    address public attacker = makeAddr("attacker");

    uint256 public constant APP_ID = 1;
    uint256 public constant VESTING_AMOUNT = 2_500_000 ether; // 25% of 10M
    uint64 public constant CLIFF_DURATION = 90 days; // 3 months
    uint64 public constant VESTING_DURATION = 730 days; // ~24 months (2 years)

    uint64 public startTime;

    function setUp() public {
        startTime = uint64(block.timestamp);

        appToken = new MockAppToken();

        vestingWallet = new AppVestingWallet(
            APP_ID, address(appToken), beneficiary, startTime, CLIFF_DURATION, VESTING_DURATION, admin
        );

        // Fund vesting wallet
        appToken.mint(address(vestingWallet), VESTING_AMOUNT);
    }

    // =========== Deployment Tests ===========

    function test_Deploy() public view {
        assertEq(vestingWallet.appId(), APP_ID);
        assertEq(vestingWallet.token(), address(appToken));
        assertEq(vestingWallet.beneficiary(), beneficiary);
        assertEq(vestingWallet.start(), startTime);
        assertEq(vestingWallet.cliff(), CLIFF_DURATION);
        assertEq(vestingWallet.duration(), VESTING_DURATION);
        assertEq(vestingWallet.admin(), admin);
    }

    function test_RevertWhen_DeployWithZeroToken() public {
        vm.expectRevert(AppVestingWallet.ZeroAddress.selector);
        new AppVestingWallet(APP_ID, address(0), beneficiary, startTime, CLIFF_DURATION, VESTING_DURATION, admin);
    }

    function test_RevertWhen_DeployWithZeroBeneficiary() public {
        vm.expectRevert(AppVestingWallet.ZeroAddress.selector);
        new AppVestingWallet(APP_ID, address(appToken), address(0), startTime, CLIFF_DURATION, VESTING_DURATION, admin);
    }

    function test_RevertWhen_DeployWithZeroAdmin() public {
        vm.expectRevert(AppVestingWallet.ZeroAddress.selector);
        new AppVestingWallet(
            APP_ID, address(appToken), beneficiary, startTime, CLIFF_DURATION, VESTING_DURATION, address(0)
        );
    }

    function test_RevertWhen_DeployWithZeroDuration() public {
        vm.expectRevert(AppVestingWallet.InvalidDuration.selector);
        new AppVestingWallet(APP_ID, address(appToken), beneficiary, startTime, CLIFF_DURATION, 0, admin);
    }

    // =========== Cliff Tests ===========

    function test_NoReleaseBeforeCliff() public {
        // Warp to just before cliff ends
        vm.warp(startTime + CLIFF_DURATION - 1);

        uint256 releasable = vestingWallet.releasable();
        assertEq(releasable, 0, "Should have 0 releasable before cliff");
    }

    function test_ReleaseStartsAfterCliff() public {
        // Warp to just after cliff ends (cliff + 1 day)
        // At exactly cliff time, vestedTime = 0, so nothing vested yet
        vm.warp(startTime + CLIFF_DURATION + 1 days);

        uint256 releasable = vestingWallet.releasable();
        assertGt(releasable, 0, "Should have releasable after cliff");
    }

    // =========== Vesting Schedule Tests ===========

    function test_VestingProgressLinear() public {
        // Warp to halfway through vesting (after cliff)
        uint256 halfwayTime = startTime + CLIFF_DURATION + (VESTING_DURATION / 2);
        vm.warp(halfwayTime);

        uint256 releasable = vestingWallet.releasable();
        // At halfway point after cliff, ~50% should be vested
        // Allow for small rounding
        assertGe(releasable, (VESTING_AMOUNT * 49) / 100, "Should have ~50% vested at halfway");
        assertLe(releasable, (VESTING_AMOUNT * 51) / 100, "Should have ~50% vested at halfway");
    }

    function test_FullVestingAtEnd() public {
        // Warp to end of vesting
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);

        uint256 releasable = vestingWallet.releasable();
        assertEq(releasable, VESTING_AMOUNT, "Should have 100% vested at end");
    }

    function test_NoAdditionalVestingAfterEnd() public {
        // Warp past end of vesting
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION + 365 days);

        uint256 releasable = vestingWallet.releasable();
        assertEq(releasable, VESTING_AMOUNT, "Should not exceed total amount");
    }

    // =========== Release Tests ===========

    function test_BeneficiaryCanRelease() public {
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);

        uint256 balanceBefore = appToken.balanceOf(beneficiary);

        vm.prank(beneficiary);
        vestingWallet.release();

        uint256 balanceAfter = appToken.balanceOf(beneficiary);
        assertEq(balanceAfter - balanceBefore, VESTING_AMOUNT);
    }

    function test_AnyoneCanTriggerRelease() public {
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);

        uint256 balanceBefore = appToken.balanceOf(beneficiary);

        // Anyone can trigger release, but tokens go to beneficiary
        vm.prank(attacker);
        vestingWallet.release();

        uint256 balanceAfter = appToken.balanceOf(beneficiary);
        assertEq(balanceAfter - balanceBefore, VESTING_AMOUNT);
    }

    function test_IncrementalRelease() public {
        // Release at cliff
        vm.warp(startTime + CLIFF_DURATION);
        uint256 firstRelease = vestingWallet.releasable();

        vm.prank(beneficiary);
        vestingWallet.release();

        assertEq(appToken.balanceOf(beneficiary), firstRelease);
        assertEq(vestingWallet.released(), firstRelease);

        // Release more later
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);
        uint256 secondRelease = vestingWallet.releasable();

        vm.prank(beneficiary);
        vestingWallet.release();

        assertEq(appToken.balanceOf(beneficiary), VESTING_AMOUNT);
        assertEq(vestingWallet.released(), VESTING_AMOUNT);
    }

    function test_ReleaseEmitsEvent() public {
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);

        vm.expectEmit(true, true, false, true);
        emit AppVestingWallet.TokensReleased(address(appToken), VESTING_AMOUNT);

        vm.prank(beneficiary);
        vestingWallet.release();
    }

    // =========== Beneficiary Management Tests ===========

    function test_AdminCanUpdateBeneficiary() public {
        vm.prank(admin);
        vestingWallet.setBeneficiary(newBeneficiary);

        assertEq(vestingWallet.beneficiary(), newBeneficiary);
    }

    function test_RevertWhen_NonAdminUpdatesBeneficiary() public {
        vm.expectRevert(AppVestingWallet.Unauthorized.selector);
        vm.prank(attacker);
        vestingWallet.setBeneficiary(newBeneficiary);
    }

    function test_RevertWhen_SetZeroBeneficiary() public {
        vm.expectRevert(AppVestingWallet.ZeroAddress.selector);
        vm.prank(admin);
        vestingWallet.setBeneficiary(address(0));
    }

    function test_BeneficiaryChangeEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit AppVestingWallet.BeneficiaryUpdated(beneficiary, newBeneficiary);

        vm.prank(admin);
        vestingWallet.setBeneficiary(newBeneficiary);
    }

    function test_NewBeneficiaryReceivesTokens() public {
        // Change beneficiary
        vm.prank(admin);
        vestingWallet.setBeneficiary(newBeneficiary);

        // Vest and release
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);
        vestingWallet.release();

        assertEq(appToken.balanceOf(newBeneficiary), VESTING_AMOUNT);
        assertEq(appToken.balanceOf(beneficiary), 0);
    }

    // =========== Admin Management Tests ===========

    function test_AdminCanTransferAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        vestingWallet.setAdmin(newAdmin);

        assertEq(vestingWallet.admin(), newAdmin);
    }

    function test_RevertWhen_NonAdminTransfersAdmin() public {
        vm.expectRevert(AppVestingWallet.Unauthorized.selector);
        vm.prank(attacker);
        vestingWallet.setAdmin(attacker);
    }

    // =========== View Functions Tests ===========

    function test_VestedAmount() public {
        // At start
        assertEq(vestingWallet.vestedAmount(), 0);

        // After cliff
        vm.warp(startTime + CLIFF_DURATION + (VESTING_DURATION / 2));
        uint256 midVested = vestingWallet.vestedAmount();
        assertGt(midVested, 0);

        // At end
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);
        assertEq(vestingWallet.vestedAmount(), VESTING_AMOUNT);
    }

    function test_TotalTokenBalance() public view {
        // Initial balance
        assertEq(vestingWallet.totalTokenBalance(), VESTING_AMOUNT);
    }

    function test_TotalTokenBalanceAfterRelease() public {
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION);
        vestingWallet.release();

        assertEq(vestingWallet.totalTokenBalance(), 0);
    }

    function test_End() public view {
        assertEq(vestingWallet.end(), startTime + CLIFF_DURATION + VESTING_DURATION);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_VestingLinear(uint256 timeElapsed) public {
        // Bound to within vesting period
        timeElapsed = bound(timeElapsed, 0, CLIFF_DURATION + VESTING_DURATION);
        vm.warp(startTime + timeElapsed);

        uint256 releasable = vestingWallet.releasable();

        if (timeElapsed < CLIFF_DURATION) {
            assertEq(releasable, 0, "Nothing releasable before cliff");
        } else {
            uint256 vestedTime = timeElapsed - CLIFF_DURATION;
            uint256 expectedMin = (VESTING_AMOUNT * vestedTime) / VESTING_DURATION;
            // Allow 1% tolerance for rounding
            assertGe(releasable, (expectedMin * 99) / 100);
        }
    }

    function testFuzz_MultipleReleases(uint32 offset1, uint32 offset2, uint32 offset3) public {
        uint256 maxOffset = uint256(CLIFF_DURATION) + uint256(VESTING_DURATION) + 365 days;

        // Bound offsets to valid range
        uint256 t1 = bound(uint256(offset1), 0, maxOffset);
        uint256 t2 = bound(uint256(offset2), 0, maxOffset);
        uint256 t3 = bound(uint256(offset3), 0, maxOffset);

        // Sort times to ensure we always go forward (simple bubble sort)
        if (t1 > t2) (t1, t2) = (t2, t1);
        if (t2 > t3) (t2, t3) = (t3, t2);
        if (t1 > t2) (t1, t2) = (t2, t1);

        uint256 totalReleased = 0;

        // Release 1
        vm.warp(startTime + t1);
        uint256 before = appToken.balanceOf(beneficiary);
        vestingWallet.release();
        totalReleased += appToken.balanceOf(beneficiary) - before;

        // Release 2
        vm.warp(startTime + t2);
        before = appToken.balanceOf(beneficiary);
        vestingWallet.release();
        totalReleased += appToken.balanceOf(beneficiary) - before;

        // Release 3
        vm.warp(startTime + t3);
        before = appToken.balanceOf(beneficiary);
        vestingWallet.release();
        totalReleased += appToken.balanceOf(beneficiary) - before;

        // Total released should never exceed vesting amount
        assertLe(totalReleased, VESTING_AMOUNT);

        // After full vesting period, should be able to claim everything
        vm.warp(startTime + CLIFF_DURATION + VESTING_DURATION + 1);
        vestingWallet.release();
        assertEq(appToken.balanceOf(beneficiary), VESTING_AMOUNT);
    }
}
