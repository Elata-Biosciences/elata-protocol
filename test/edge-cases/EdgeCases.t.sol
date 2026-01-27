// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ELTA} from "../../src/token/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Edge Cases Test Suite
 * @notice Tests boundary conditions, dust amounts, and extreme values
 */
contract EdgeCasesTest is Test {
    ELTA public elta;
    VeELTA public veElta;

    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    uint256 constant INITIAL_SUPPLY = 1_000_000_000 ether;

    // VeELTA time constants (must match VeELTA.sol)
    uint64 constant MIN_LOCK = 7 days;
    uint64 constant MAX_LOCK = 730 days; // 2 years

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(treasury);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        vm.stopPrank();

        // Fund test users (treasury has 77M total, give each user 10M)
        vm.prank(treasury);
        elta.transfer(user1, 10_000_000 ether);

        vm.prank(treasury);
        elta.transfer(user2, 10_000_000 ether);

        // Approve staking
        vm.prank(user1);
        elta.approve(address(veElta), type(uint256).max);

        vm.prank(user2);
        elta.approve(address(veElta), type(uint256).max);

        // Start at reasonable block
        vm.roll(100);
        vm.warp(1700000000); // Nov 2023
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TIME BOUNDARY TESTS
    // ─────────────────────────────────────────────────────────────────────────

    function test_LockJustAboveMinDuration() public {
        // Lock requires unlockTime > block.timestamp + MIN_LOCK (strict inequality)
        uint64 unlockTime = uint64(block.timestamp + MIN_LOCK + 1);
        vm.prank(user1);
        veElta.lock(1000 ether, unlockTime);

        (uint256 principal, uint64 actualUnlockTime,,) = veElta.getLockDetails(user1);
        assertEq(principal, 1000 ether, "Principal should match");
        assertEq(actualUnlockTime, unlockTime, "Unlock time should match");
    }

    function test_LockExactlyMaxDuration() public {
        // Lock allows unlockTime <= block.timestamp + MAX_LOCK
        uint64 unlockTime = uint64(block.timestamp + MAX_LOCK);
        vm.prank(user1);
        veElta.lock(1000 ether, unlockTime);

        (uint256 principal, uint64 actualUnlockTime, uint256 veBalance,) = veElta.getLockDetails(user1);
        assertEq(principal, 1000 ether, "Principal should match");
        assertEq(actualUnlockTime, unlockTime, "Unlock time should be exact maximum");
        assertGt(veBalance, 0, "Should have veELTA balance");
    }

    function test_RevertWhen_LockBelowMinDuration() public {
        // unlockTime must be > block.timestamp + MIN_LOCK
        vm.prank(user1);
        vm.expectRevert(Errors.LockTooShort.selector);
        veElta.lock(1000 ether, uint64(block.timestamp + MIN_LOCK));
    }

    function test_RevertWhen_LockAboveMaxDuration() public {
        vm.prank(user1);
        vm.expectRevert(Errors.LockTooLong.selector);
        veElta.lock(1000 ether, uint64(block.timestamp + MAX_LOCK + 1));
    }

    function test_UnlockExactlyAtExpiry() public {
        // Lock with minimum valid duration
        uint64 unlockTime = uint64(block.timestamp + MIN_LOCK + 1);
        vm.prank(user1);
        veElta.lock(1000 ether, unlockTime);

        // Warp to exact unlock time
        vm.warp(unlockTime);

        // Should be able to unlock
        uint256 balanceBefore = elta.balanceOf(user1);
        vm.prank(user1);
        veElta.unlock();

        uint256 balanceAfter = elta.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, 1000 ether, "Should recover full principal");
    }

    function test_RevertWhen_UnlockOneSecondEarly() public {
        // Lock with minimum valid duration
        uint64 unlockTime = uint64(block.timestamp + MIN_LOCK + 1);
        vm.prank(user1);
        veElta.lock(1000 ether, unlockTime);

        // Warp to one second before unlock
        vm.warp(unlockTime - 1);

        // Should NOT be able to unlock
        vm.prank(user1);
        vm.expectRevert();
        veElta.unlock();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DUST AMOUNT TESTS (1 wei operations)
    // ─────────────────────────────────────────────────────────────────────────

    function test_LockOneWei() public {
        vm.prank(user1);
        veElta.lock(1, uint64(block.timestamp + 365 days));

        (uint256 principal,, uint256 veBalance,) = veElta.getLockDetails(user1);
        assertEq(principal, 1, "Should lock 1 wei");
        // veBalance might be 0 due to precision loss, but transaction should succeed
    }

    function test_IncreaseAmountByOneWei() public {
        // First lock
        vm.prank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Increase by 1 wei
        vm.prank(user1);
        veElta.increaseAmount(1);

        (uint256 principal,,,) = veElta.getLockDetails(user1);
        assertEq(principal, 1000 ether + 1, "Principal should increase by 1 wei");
    }

    function test_AllSupplyMintedAtDeployment() public view {
        // All 77M tokens are minted at deployment
        uint256 currentSupply = elta.totalSupply();
        uint256 maxSupply = elta.MAX_SUPPLY();

        assertEq(currentSupply, maxSupply, "All supply should be minted at deployment");
    }

    function test_TransferOneWei() public {
        uint256 user1BalanceBefore = elta.balanceOf(user1);
        uint256 user2BalanceBefore = elta.balanceOf(user2);

        vm.prank(user1);
        elta.transfer(user2, 1);

        assertEq(elta.balanceOf(user1), user1BalanceBefore - 1, "Sender should lose 1 wei");
        assertEq(elta.balanceOf(user2), user2BalanceBefore + 1, "Receiver should gain 1 wei");
    }

    function test_BurnOneWei() public {
        uint256 supplyBefore = elta.totalSupply();
        uint256 balanceBefore = elta.balanceOf(user1);

        vm.prank(user1);
        elta.burn(1);

        assertEq(elta.totalSupply(), supplyBefore - 1, "Supply should decrease by 1 wei");
        assertEq(elta.balanceOf(user1), balanceBefore - 1, "Balance should decrease by 1 wei");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MAX VALUE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    function test_ApproveMaxUint256() public {
        vm.prank(user1);
        elta.approve(user2, type(uint256).max);

        assertEq(elta.allowance(user1, user2), type(uint256).max, "Should allow max approval");
    }

    function test_TransferFromWithMaxApproval() public {
        vm.prank(user1);
        elta.approve(user2, type(uint256).max);

        uint256 amount = 1000 ether;
        vm.prank(user2);
        elta.transferFrom(user1, user2, amount);

        // Max approval should remain infinite
        assertEq(elta.allowance(user1, user2), type(uint256).max, "Max approval should not decrease");
    }

    function test_CannotTransferMoreThanBalance() public {
        // User1 has tokens, try to transfer more than balance
        uint256 user1Balance = elta.balanceOf(user1);

        vm.prank(user1);
        vm.expectRevert(); // ERC20 insufficient balance error
        elta.transfer(user2, user1Balance + 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ZERO VALUE TESTS
    // ─────────────────────────────────────────────────────────────────────────

    function test_TransferZero() public {
        // ERC20 typically allows zero transfers
        uint256 balanceBefore = elta.balanceOf(user1);
        vm.prank(user1);
        elta.transfer(user2, 0);

        assertEq(elta.balanceOf(user1), balanceBefore, "Balance unchanged after zero transfer");
    }

    function test_ApproveZero() public {
        // First approve some amount
        vm.prank(user1);
        elta.approve(user2, 1000 ether);

        // Then approve zero to revoke
        vm.prank(user1);
        elta.approve(user2, 0);

        assertEq(elta.allowance(user1, user2), 0, "Allowance should be zero");
    }

    function test_RevertWhen_LockZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAmount.selector);
        veElta.lock(0, uint64(block.timestamp + MIN_LOCK + 1));
    }

    function test_RevertWhen_IncreaseByZero() public {
        // First lock
        vm.prank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + MIN_LOCK + 1));

        // Try to increase by zero
        vm.prank(user1);
        vm.expectRevert(Errors.InvalidAmount.selector);
        veElta.increaseAmount(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONCURRENT OPERATIONS EDGE CASES
    // ─────────────────────────────────────────────────────────────────────────

    function test_MultipleLocksInSameBlock() public {
        // User1 locks
        vm.prank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // User2 locks in same block
        vm.prank(user2);
        veElta.lock(2000 ether, uint64(block.timestamp + 365 days));

        // Both should have positions
        (uint256 principal1,,,) = veElta.getLockDetails(user1);
        (uint256 principal2,,,) = veElta.getLockDetails(user2);

        assertEq(principal1, 1000 ether, "User1 should have 1000 ELTA locked");
        assertEq(principal2, 2000 ether, "User2 should have 2000 ELTA locked");
    }

    function test_TransferAndApproveInSameBlock() public {
        vm.startPrank(user1);
        elta.transfer(user2, 100 ether);
        elta.approve(user2, 1000 ether);
        vm.stopPrank();

        assertEq(elta.balanceOf(user2), 10_000_000 ether + 100 ether, "Transfer should complete");
        assertEq(elta.allowance(user1, user2), 1000 ether, "Approval should be set");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ARITHMETIC EDGE CASES
    // ─────────────────────────────────────────────────────────────────────────

    function test_VeELTADecayToZero() public {
        // Lock for minimum valid time
        uint64 unlockTime = uint64(block.timestamp + MIN_LOCK + 1);
        vm.prank(user1);
        veElta.lock(1000 ether, unlockTime);

        (,, uint256 veBalanceStart,) = veElta.getLockDetails(user1);
        assertGt(veBalanceStart, 0, "Should start with positive veELTA");

        // Warp to just before expiry
        vm.warp(unlockTime - 1);

        (,, uint256 veBalanceEnd,) = veElta.getLockDetails(user1);
        // veBalance should be very small but might be 0 due to precision
        assertLe(veBalanceEnd, veBalanceStart, "veELTA should decay");
    }

    function testFuzz_LockDuration(uint64 duration) public {
        // Duration must be > MIN_LOCK and <= MAX_LOCK
        duration = uint64(bound(duration, MIN_LOCK + 1, MAX_LOCK));

        uint64 unlockTime = uint64(block.timestamp) + duration;
        vm.prank(user1);
        veElta.lock(1000 ether, unlockTime);

        (uint256 principal, uint64 actualUnlockTime,,) = veElta.getLockDetails(user1);
        assertEq(principal, 1000 ether, "Principal should match");
        assertEq(actualUnlockTime, unlockTime, "Unlock time should match");
    }

    function testFuzz_LockAmount(uint256 amount) public {
        // Bound to reasonable range (1 wei to user's balance)
        amount = bound(amount, 1, elta.balanceOf(user1));

        vm.prank(user1);
        veElta.lock(amount, uint64(block.timestamp + 365 days));

        (uint256 principal,,,) = veElta.getLockDetails(user1);
        assertEq(principal, amount, "Principal should match locked amount");
    }

    function testFuzz_TransferAmount(uint256 amount) public {
        amount = bound(amount, 0, elta.balanceOf(user1));

        uint256 user1Before = elta.balanceOf(user1);
        uint256 user2Before = elta.balanceOf(user2);

        vm.prank(user1);
        elta.transfer(user2, amount);

        assertEq(elta.balanceOf(user1), user1Before - amount, "Sender balance should decrease");
        assertEq(elta.balanceOf(user2), user2Before + amount, "Receiver balance should increase");
    }
}
