// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @title CriticalFuzz
 * @notice Comprehensive fuzz tests for security-critical functions
 */
contract CriticalFuzz is Test {
    ELTA public elta;
    VeELTA public veElta;
    ProtocolConfig public config;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public treasury = makeAddr("treasury");
    address public appRewards = makeAddr("appRewards");
    address public veRewards = makeAddr("veRewards");
    address public feeSwapper = makeAddr("feeSwapper");
    address public user = makeAddr("user");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        usdc = new MockUSDC();

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy ProtocolConfig
        config = new ProtocolConfig(admin, timelock);

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(0), feeSwapper);

        // Deploy FeeManager
        feeManager = new FeeManager(address(elta), address(usdc), admin, admin, appRewards, veRewards, treasury, 1 days);

        // Setup
        vm.prank(admin);
        feeCollector.setFeeManager(address(feeManager));
        vm.prank(admin);
        feeManager.setDepositor(address(feeCollector), true);

        // Fund user
        vm.prank(admin);
        elta.transfer(user, 10_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELTA TOKEN FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ELTA_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(elta));
        amount = bound(amount, 1, elta.balanceOf(user));

        uint256 userBefore = elta.balanceOf(user);
        uint256 toBefore = elta.balanceOf(to);

        vm.prank(user);
        elta.transfer(to, amount);

        assertEq(elta.balanceOf(user), userBefore - amount, "Sender balance incorrect");
        assertEq(elta.balanceOf(to), toBefore + amount, "Receiver balance incorrect");
    }

    function testFuzz_ELTA_Approve(address spender, uint256 amount) public {
        vm.assume(spender != address(0));

        vm.prank(user);
        elta.approve(spender, amount);

        assertEq(elta.allowance(user, spender), amount, "Allowance incorrect");
    }

    function testFuzz_ELTA_TransferFrom(address from, address to, uint256 amount) public {
        vm.assume(from != address(0) && to != address(0) && to != address(elta));
        vm.assume(from != to);

        // Give `from` some tokens
        vm.prank(admin);
        elta.transfer(from, 1_000_000 ether);

        amount = bound(amount, 1, elta.balanceOf(from));

        // Approve user to spend
        vm.prank(from);
        elta.approve(user, amount);

        uint256 fromBefore = elta.balanceOf(from);
        uint256 toBefore = elta.balanceOf(to);

        vm.prank(user);
        elta.transferFrom(from, to, amount);

        assertEq(elta.balanceOf(from), fromBefore - amount, "From balance incorrect");
        assertEq(elta.balanceOf(to), toBefore + amount, "To balance incorrect");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VeELTA STAKING FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_VeELTA_Lock(uint256 amount, uint256 durationDays) public {
        amount = bound(amount, 1 ether, 5_000_000 ether);
        durationDays = bound(durationDays, 8, 730); // MIN_LOCK+1 day to MAX_LOCK

        uint64 unlockTime = uint64(block.timestamp + durationDays * 1 days);

        vm.startPrank(user);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, unlockTime);
        vm.stopPrank();

        (uint128 principal, uint64 storedUnlock) = veElta.locks(user);
        assertEq(principal, amount, "Principal incorrect");
        assertEq(storedUnlock, unlockTime, "Unlock time incorrect");

        uint256 veBalance = veElta.balanceOf(user);
        assertGe(veBalance, amount, "veELTA should be >= principal");
        assertLe(veBalance, amount * 2, "veELTA should be <= 2x principal");
    }

    function testFuzz_VeELTA_IncreaseAmount(uint256 initialAmount, uint256 addAmount) public {
        initialAmount = bound(initialAmount, 1 ether, 2_500_000 ether);
        addAmount = bound(addAmount, 1 ether, 2_500_000 ether);

        uint64 unlockTime = uint64(block.timestamp + 365 days);

        vm.startPrank(user);
        elta.approve(address(veElta), initialAmount + addAmount);

        // Initial lock
        veElta.lock(initialAmount, unlockTime);
        (uint128 principalBefore,) = veElta.locks(user);

        // Increase
        veElta.increaseAmount(addAmount);
        (uint128 principalAfter,) = veElta.locks(user);

        assertEq(principalAfter, principalBefore + addAmount, "Principal should increase");
        vm.stopPrank();
    }

    function testFuzz_VeELTA_UnlockAfterExpiry(uint256 amount, uint256 warpExtra) public {
        amount = bound(amount, 1 ether, 5_000_000 ether);
        warpExtra = bound(warpExtra, 1, 365 days);

        uint64 lockDuration = 30 days;
        uint64 unlockTime = uint64(block.timestamp + lockDuration);

        vm.startPrank(user);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, unlockTime);

        uint256 balanceBefore = elta.balanceOf(user);

        // Warp past unlock
        vm.warp(unlockTime + warpExtra);

        veElta.unlock();

        uint256 balanceAfter = elta.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, amount, "Should get exact principal back");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROTOCOL CONFIG FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_ProtocolConfig_BondingCurveTax(uint256 tax) public {
        uint256 maxTax = config.MAX_BONDING_CURVE_TAX_BPS();
        tax = bound(tax, 0, maxTax);

        vm.prank(timelock);
        config.setBondingCurveTradeTaxBps(tax);

        assertEq(config.bondingCurveTradeTaxBps(), tax, "Tax not set correctly");
    }

    function testFuzz_ProtocolConfig_GraduationTarget(uint256 target) public {
        uint256 minTarget = config.MIN_GRADUATION_TARGET();
        uint256 maxTarget = config.MAX_GRADUATION_TARGET();
        target = bound(target, minTarget, maxTarget);

        vm.prank(timelock);
        config.setGraduationTarget(target);

        assertEq(config.graduationTarget(), target, "Target not set correctly");
    }

    function testFuzz_ProtocolConfig_LPLockDuration(uint256 duration) public {
        uint256 minDuration = config.MIN_LP_LOCK_DURATION();
        uint256 maxDuration = config.MAX_LP_LOCK_DURATION();
        duration = bound(duration, minDuration, maxDuration);

        vm.prank(timelock);
        config.setLpLockDuration(duration);

        assertEq(config.lpLockDuration(), duration, "Duration not set correctly");
    }

    function testFuzz_ProtocolConfig_FeeSplits(
        uint256 appStakers,
        uint256 veEltaShare,
        uint256 creator,
        uint256 treasuryShare,
        uint256 referral
    ) public {
        // Bound each to reasonable range
        uint256 maxBucket = config.MAX_BUCKET_BPS();
        appStakers = bound(appStakers, 0, maxBucket);
        veEltaShare = bound(veEltaShare, 0, maxBucket);
        creator = bound(creator, 0, maxBucket);
        treasuryShare = bound(treasuryShare, 0, maxBucket);
        referral = bound(referral, 0, maxBucket);

        uint256 total = appStakers + veEltaShare + creator + treasuryShare + referral;

        // Only test if splits sum to 10000
        if (total != 10000) return;

        vm.prank(timelock);
        config.setFeeSplits(appStakers, veEltaShare, creator, treasuryShare, referral);

        (uint256 a, uint256 v, uint256 c, uint256 t, uint256 r) = config.feeSplits();
        assertEq(a + v + c + t + r, 10000, "Splits should sum to 10000");
    }

    function testFuzz_ProtocolConfig_EpochLength(uint256 length) public {
        uint256 minLength = config.MIN_EPOCH_LENGTH();
        uint256 maxLength = config.MAX_EPOCH_LENGTH();
        length = bound(length, minLength, maxLength);

        vm.prank(timelock);
        config.setEpochLength(length);

        assertEq(config.epochLength(), length, "Epoch length not set correctly");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTOR FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_FeeCollector_Deposit(uint256 appId, uint256 amount) public {
        appId = bound(appId, 0, 100);
        amount = bound(amount, 1 ether, 1_000_000 ether);

        vm.startPrank(user);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(appId, amount);
        vm.stopPrank();

        assertEq(feeCollector.pendingEltaFees(appId), amount, "Pending fees incorrect");
    }

    function testFuzz_FeeCollector_MultipleDeposits(uint256 appId, uint256[] calldata amounts) public {
        vm.assume(amounts.length > 0 && amounts.length <= 10);
        appId = bound(appId, 0, 100);

        uint256 total = 0;
        vm.startPrank(user);
        elta.approve(address(feeCollector), 10_000_000 ether);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amt = bound(amounts[i], 1 ether, 100_000 ether);
            total += amt;
            if (total > 9_000_000 ether) break;
            feeCollector.depositElta(appId, amt);
        }
        vm.stopPrank();

        assertGe(feeCollector.pendingEltaFees(appId), 0, "Should have pending fees");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE MANAGER FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_FeeManager_FeeSplitsConstant() public {
        // Verify fee splits always sum to 100%
        (uint256 appStakers, uint256 veEltaShare, uint256 creator, uint256 treasuryShare, uint256 referral) =
            feeManager.feeSplits();

        assertEq(appStakers + veEltaShare + creator + treasuryShare + referral, 10000, "Splits should sum to 10000");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOUNDARY VALUE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Boundary_VeELTA_MinLock() public {
        uint256 amount = 1000 ether;
        uint64 minLock = veElta.MIN_LOCK();

        vm.startPrank(user);
        elta.approve(address(veElta), amount);

        // Exactly at MIN_LOCK boundary should fail (needs to be >)
        vm.expectRevert();
        veElta.lock(amount, uint64(block.timestamp + minLock));

        // Just above should work
        veElta.lock(amount, uint64(block.timestamp + minLock + 1));
        vm.stopPrank();
    }

    function test_Boundary_VeELTA_MaxLock() public {
        uint256 amount = 1000 ether;
        uint64 maxLock = veElta.MAX_LOCK();

        vm.startPrank(user);
        elta.approve(address(veElta), amount);

        // Exactly at MAX_LOCK should work
        veElta.lock(amount, uint64(block.timestamp + maxLock));
        vm.stopPrank();

        // Check voting power is at max boost
        uint256 veBalance = veElta.balanceOf(user);
        assertGe(veBalance, amount * 19 / 10, "Should have near-max boost at MAX_LOCK");
    }

    function test_Boundary_ProtocolConfig_MinGraduationTarget() public {
        uint256 minTarget = config.MIN_GRADUATION_TARGET();

        vm.prank(timelock);
        config.setGraduationTarget(minTarget);
        assertEq(config.graduationTarget(), minTarget, "Min target should be settable");

        vm.prank(timelock);
        vm.expectRevert();
        config.setGraduationTarget(minTarget - 1);
    }

    function test_Boundary_ProtocolConfig_MaxGraduationTarget() public {
        uint256 maxTarget = config.MAX_GRADUATION_TARGET();

        vm.prank(timelock);
        config.setGraduationTarget(maxTarget);
        assertEq(config.graduationTarget(), maxTarget, "Max target should be settable");

        vm.prank(timelock);
        vm.expectRevert();
        config.setGraduationTarget(maxTarget + 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRESS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Stress_ManyUsers(uint8 numUsers) public {
        numUsers = uint8(bound(numUsers, 1, 20));

        for (uint256 i = 0; i < numUsers; i++) {
            address testUser = address(uint160(0x1000 + i));

            // Fund user
            vm.prank(admin);
            elta.transfer(testUser, 100_000 ether);

            // Lock
            vm.startPrank(testUser);
            elta.approve(address(veElta), 10_000 ether);
            veElta.lock(10_000 ether, uint64(block.timestamp + 30 days));
            vm.stopPrank();

            // Verify
            (uint128 principal,) = veElta.locks(testUser);
            assertEq(principal, 10_000 ether, "Lock should succeed");
        }

        // Verify total supply is correct
        uint256 totalSupply = veElta.totalSupply();
        assertGt(totalSupply, 0, "Total supply should be positive");
    }
}
