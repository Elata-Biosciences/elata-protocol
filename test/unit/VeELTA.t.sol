// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { Errors } from "../../src/utils/Errors.sol";

/**
 * @title VeELTA V2 Tests
 * @notice Unit tests for ERC20Votes-based veELTA
 * @dev V2 architecture: ERC721 NFT → ERC20Votes (non-transferable)
 *      - Single lock per user
 *      - Duration boost (1x to 2x)
 *      - No continuous decay
 *      - Snapshot-enabled
 */
contract VeELTATest is Test {
    VeELTA public veElta;
    ELTA public elta;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    event Locked(address indexed user, uint256 amount, uint64 unlockTime, uint256 veELTA);
    event AmountIncreased(
        address indexed user, uint256 addAmount, uint256 newPrincipal, uint256 newVeELTA
    );
    event LockExtended(
        address indexed user, uint64 oldUnlockTime, uint64 newUnlockTime, uint256 newVeELTA
    );
    event Unlocked(address indexed user, uint256 principal, uint256 veELTABurned);

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 0);
        veElta = new VeELTA(elta, admin);

        // Fund users
        vm.startPrank(treasury);
        elta.transfer(user1, 100_000 ether);
        elta.transfer(user2, 100_000 ether);
        vm.stopPrank();

        // Approvals
        vm.prank(user1);
        elta.approve(address(veElta), type(uint256).max);
        vm.prank(user2);
        elta.approve(address(veElta), type(uint256).max);
    }

    function test_Deployment() public view {
        assertEq(address(veElta.ELTA()), address(elta));
        assertEq(veElta.name(), "veELTA Voting Power");
        assertEq(veElta.symbol(), "veELTA");
        assertEq(veElta.MIN_LOCK(), 7 days);
        assertEq(veElta.MAX_LOCK(), 730 days);
    }

    function test_Lock_MaxDuration() public {
        uint256 amount = 1000 ether;
        uint64 unlockTime = uint64(block.timestamp + 730 days);

        vm.expectEmit(true, false, false, false);
        emit Locked(user1, amount, unlockTime, 2000 ether);

        vm.prank(user1);
        veElta.lock(amount, unlockTime);

        // Check lock details
        (uint256 principal, uint64 storedUnlockTime, uint256 veBalance,) =
            veElta.getLockDetails(user1);
        assertEq(principal, amount);
        assertEq(storedUnlockTime, unlockTime);

        // Max lock = 2x boost
        assertEq(veBalance, amount * 2);
        assertEq(veElta.balanceOf(user1), amount * 2);
    }

    function test_Lock_MinDuration() public {
        uint256 amount = 1000 ether;
        uint64 unlockTime = uint64(block.timestamp + 8 days); // MIN_LOCK + 1

        vm.prank(user1);
        veElta.lock(amount, unlockTime);

        // Close to min lock has small boost (linear interpolation)
        // 8 days / 730 days * 1e18 boost range ≈ 1.01x
        assertGt(veElta.balanceOf(user1), amount);
        assertLt(veElta.balanceOf(user1), amount * 11 / 10); // Less than 1.1x
    }

    function test_Lock_RevertIfTooShort() public {
        uint64 tooShort = uint64(block.timestamp + 6 days);

        vm.prank(user1);
        vm.expectRevert(Errors.LockTooShort.selector);
        veElta.lock(1000 ether, tooShort);
    }

    function test_Lock_RevertIfTooLong() public {
        uint64 tooLong = uint64(block.timestamp + 731 days);

        vm.prank(user1);
        vm.expectRevert(Errors.LockTooLong.selector);
        veElta.lock(1000 ether, tooLong);
    }

    function test_Lock_RevertIfAlreadyExists() public {
        vm.startPrank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        vm.expectRevert(VeELTA.LockExists.selector);
        veElta.lock(500 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();
    }

    function test_IncreaseAmount() public {
        // Create initial lock
        vm.prank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        uint256 initialVeBalance = veElta.balanceOf(user1);

        // Increase amount
        vm.expectEmit(true, false, false, false);
        emit AmountIncreased(user1, 500 ether, 1500 ether, 0);

        vm.prank(user1);
        veElta.increaseAmount(500 ether);

        // Check updated lock
        (uint256 principal,,,) = veElta.getLockDetails(user1);
        assertEq(principal, 1500 ether);

        // veELTA balance should increase
        assertGt(veElta.balanceOf(user1), initialVeBalance);
    }

    function test_ExtendLock() public {
        // Create initial lock for 1 year
        uint64 initialUnlock = uint64(block.timestamp + 365 days);
        vm.prank(user1);
        veElta.lock(1000 ether, initialUnlock);

        uint256 initialVeBalance = veElta.balanceOf(user1);

        // Extend to 2 years
        uint64 newUnlock = uint64(block.timestamp + 730 days);

        vm.expectEmit(true, false, false, false);
        emit LockExtended(user1, initialUnlock, newUnlock, 0);

        vm.prank(user1);
        veElta.extendLock(newUnlock);

        // Check updated unlock time
        (, uint64 unlockTime,,) = veElta.getLockDetails(user1);
        assertEq(unlockTime, newUnlock);

        // veELTA balance should increase (longer duration = higher boost)
        assertGt(veElta.balanceOf(user1), initialVeBalance);
    }

    function test_Unlock() public {
        uint64 unlockTime = uint64(block.timestamp + 365 days);
        uint256 lockAmount = 1000 ether;

        vm.prank(user1);
        veElta.lock(lockAmount, unlockTime);

        // Can't unlock before expiry
        vm.prank(user1);
        vm.expectRevert(Errors.LockNotExpired.selector);
        veElta.unlock();

        // Fast forward past expiry
        vm.warp(unlockTime + 1);

        uint256 user1BalanceBefore = elta.balanceOf(user1);
        uint256 veBalanceBefore = veElta.balanceOf(user1);

        vm.expectEmit(true, false, false, false);
        emit Unlocked(user1, lockAmount, veBalanceBefore);

        vm.prank(user1);
        veElta.unlock();

        // Check ELTA returned 1:1
        assertEq(elta.balanceOf(user1), user1BalanceBefore + lockAmount);

        // veELTA balance burned
        assertEq(veElta.balanceOf(user1), 0);

        // Lock cleared
        (uint256 principal,,,) = veElta.getLockDetails(user1);
        assertEq(principal, 0);
    }

    function test_NonTransferable() public {
        vm.prank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        uint256 user1Balance = veElta.balanceOf(user1);

        // Try to transfer veELTA - should fail
        vm.prank(user1);
        vm.expectRevert(Errors.NonTransferable.selector);
        veElta.transfer(user2, user1Balance);

        // Balance unchanged
        assertEq(veElta.balanceOf(user1), user1Balance);
        assertEq(veElta.balanceOf(user2), 0);
    }

    function test_Snapshots_GetPastVotes() public {
        vm.roll(100);

        vm.prank(user1);
        veElta.lock(1000 ether, uint64(block.timestamp + 730 days));

        // Roll forward after lock to ensure checkpoint is created
        vm.roll(101);

        uint256 veBalance = veElta.getVotes(user1);

        // Roll forward more to make checkpoint well in past
        vm.roll(200);

        // Should be able to query past votes at block 101
        uint256 pastVotes = veElta.getPastVotes(user1, 101);
        assertEq(pastVotes, veBalance);
    }

    function test_AdminMint() public {
        vm.prank(admin);
        veElta.mint(user1, 1000 ether);

        assertEq(veElta.balanceOf(user1), 1000 ether);
    }

    function test_AdminBurn() public {
        vm.prank(admin);
        veElta.mint(user1, 1000 ether);

        vm.prank(admin);
        veElta.burn(user1, 500 ether);

        assertEq(veElta.balanceOf(user1), 500 ether);
    }
}
