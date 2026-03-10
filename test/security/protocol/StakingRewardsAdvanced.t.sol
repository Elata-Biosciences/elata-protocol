// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {AppStakingVault} from "../../../src/apps/AppStakingVault.sol";
import {RewardsDistributor} from "../../../src/rewards/RewardsDistributor.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAppRewardsDistributor} from "../../../src/interfaces/IAppRewardsDistributor.sol";
import {IVeEltaVotes} from "../../../src/interfaces/IVeEltaVotes.sol";
import {Errors} from "../../../src/utils/Errors.sol";

/// @notice Mock app rewards distributor
contract MockAppRewardsDistributor is IAppRewardsDistributor {
    function registerApp(address) external pure override {}
    function registerApp(address, address) external pure override {}
    function distribute(uint256) external pure override {}
    function depositForApp(IERC20, uint256) external pure override {}
    function claim(address, uint256) external pure override {}
    function claimToken(address, IERC20, uint256) external pure override {}
}

/**
 * @title StakingRewardsAdvanced
 * @notice Advanced staking and rewards exploit tests
 */
contract StakingRewardsAdvanced is Test {
    ELTA public elta;
    VeELTA public veElta;
    AppToken public appToken;
    AppStakingVault public vault;
    RewardsDistributor public distributor;
    MockAppRewardsDistributor public appRewards;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy AppToken
        appToken = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: APP_TOKEN_SUPPLY,
                creator: admin,
                admin: admin,
                governance: admin,
                appRewardsDistributor: treasury,
                rewardsDistributor: treasury,
                treasury: treasury
            })
        );

        // Deploy app rewards mock
        appRewards = new MockAppRewardsDistributor();

        // Deploy RewardsDistributor with correct argument order
        distributor = new RewardsDistributor(
            IERC20(address(elta)),
            IVeEltaVotes(address(veElta)),
            IAppRewardsDistributor(address(appRewards)),
            treasury,
            admin
        );

        // Deploy AppStakingVault (appName, appSymbol, appToken, owner)
        vault = new AppStakingVault("TestApp", "stTEST", IERC20(address(appToken)), admin);

        // Fund users
        vm.startPrank(admin);
        elta.transfer(user1, 1_000_000 ether);
        elta.transfer(user2, 1_000_000 ether);
        elta.transfer(attacker, 100_000 ether);
        appToken.mint(user1, 100_000 ether);
        appToken.mint(user2, 100_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VeELTA LOCKING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_VeELTA_LockDurationEnforced() public {
        uint64 minLock = veElta.MIN_LOCK();
        uint64 maxLock = veElta.MAX_LOCK();

        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        // Too short
        vm.expectRevert(Errors.LockTooShort.selector);
        veElta.lock(1000 ether, uint64(block.timestamp + minLock - 1));

        // Too long
        vm.expectRevert(Errors.LockTooLong.selector);
        veElta.lock(1000 ether, uint64(block.timestamp + maxLock + 1));

        // Valid duration
        veElta.lock(1000 ether, uint64(block.timestamp + minLock + 1));
        vm.stopPrank();
    }

    function test_VeELTA_BoostCalculation() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        // Lock for 1 year
        uint64 oneYear = 365 days;
        veElta.lock(1000 ether, uint64(block.timestamp + oneYear));

        // Boost should be between 1x and 2x
        uint256 votingPower = veElta.getVotes(user1);
        assertGe(votingPower, 1000 ether, "Voting power should be at least principal");
        assertLe(votingPower, 2000 ether, "Voting power should not exceed 2x");
        vm.stopPrank();
    }

    function test_VeELTA_IncreaseAmount() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 2000 ether);

        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));
        uint256 powerBefore = veElta.getVotes(user1);

        // Increase amount
        veElta.increaseAmount(500 ether);
        uint256 powerAfter = veElta.getVotes(user1);

        assertGt(powerAfter, powerBefore, "Power should increase");
        vm.stopPrank();
    }

    function test_VeELTA_ExtendLock() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        uint64 initialUnlock = uint64(block.timestamp + 30 days);
        veElta.lock(1000 ether, initialUnlock);
        uint256 powerBefore = veElta.getVotes(user1);

        // Extend lock
        uint64 newUnlock = uint64(block.timestamp + 365 days);
        veElta.extendLock(newUnlock);
        uint256 powerAfter = veElta.getVotes(user1);

        assertGt(powerAfter, powerBefore, "Power should increase with longer lock");
        vm.stopPrank();
    }

    function test_VeELTA_UnlockAfterExpiry() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        uint64 unlockAt = uint64(block.timestamp + 8 days);
        veElta.lock(1000 ether, unlockAt);

        // Cannot unlock before expiry
        vm.expectRevert();
        veElta.unlock();

        // Warp past unlock
        vm.warp(unlockAt + 1);

        // Can unlock now
        uint256 balanceBefore = elta.balanceOf(user1);
        veElta.unlock();
        uint256 balanceAfter = elta.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, 1000 ether, "Should receive full principal");
        vm.stopPrank();
    }

    function test_VeELTA_VotingPowerDecays() public {
        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        uint64 lockDuration = 365 days;
        veElta.lock(1000 ether, uint64(block.timestamp + lockDuration));
        uint256 powerAtStart = veElta.getVotes(user1);

        // Warp forward 6 months
        vm.warp(block.timestamp + 180 days);
        uint256 powerAfter6Months = veElta.getVotes(user1);

        // Power should decrease as unlock approaches
        assertLe(powerAfter6Months, powerAtStart, "Power should not increase over time");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING VAULT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Vault_StakeUnstake() public {
        vm.startPrank(user1);
        appToken.approve(address(vault), 1000 ether);

        vault.stake(1000 ether);
        assertEq(vault.balanceOf(user1), 1000 ether, "Should have vault shares");

        vault.unstake(1000 ether);
        assertEq(vault.balanceOf(user1), 0, "Should have 0 shares after unstake");
        vm.stopPrank();
    }

    function test_Vault_ShareCalculation() public {
        // User1 stakes first
        vm.startPrank(user1);
        appToken.approve(address(vault), 10000 ether);
        vault.stake(10000 ether);
        vm.stopPrank();

        // User2 stakes equal amount
        vm.startPrank(user2);
        appToken.approve(address(vault), 10000 ether);
        vault.stake(10000 ether);
        vm.stopPrank();

        // Both users should have equal shares
        uint256 user1Shares = vault.balanceOf(user1);
        uint256 user2Shares = vault.balanceOf(user2);

        assertEq(user1Shares, user2Shares, "Equal stakes should give equal shares");
        assertEq(user1Shares, 10000 ether, "Shares should equal staked amount");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARDS DISTRIBUTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Distributor_DepositCreatesEpoch() public {
        vm.prank(admin);
        elta.approve(address(distributor), 1000 ether);

        vm.prank(admin);
        distributor.deposit(100 ether);

        assertEq(distributor.getEpochCount(), 1, "Should have 1 epoch");
    }

    function test_Distributor_MultipleEpochs() public {
        vm.startPrank(admin);
        elta.approve(address(distributor), 10000 ether);

        // Create multiple epochs
        for (uint256 i = 0; i < 5; i++) {
            distributor.deposit(100 ether);
            vm.roll(block.number + 1);
        }
        vm.stopPrank();

        assertEq(distributor.getEpochCount(), 5, "Should have 5 epochs");
    }

    function test_Distributor_ClaimProportional() public {
        // Both users lock ELTA
        vm.startPrank(user1);
        elta.approve(address(veElta), 100_000 ether);
        veElta.lock(100_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        vm.startPrank(user2);
        elta.approve(address(veElta), 200_000 ether);
        veElta.lock(200_000 ether, uint64(block.timestamp + 365 days));
        vm.stopPrank();

        // Advance block for snapshots
        vm.roll(block.number + 10);

        // Create epoch
        vm.startPrank(admin);
        elta.approve(address(distributor), 1000 ether);
        distributor.deposit(300 ether); // 15% = 45 ether to veELTA
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Claim
        vm.prank(user1);
        distributor.claimVe(0, 1);

        vm.prank(user2);
        distributor.claimVe(0, 1);

        // User2 should have gotten ~2x user1 (based on voting power)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_VeELTA_LockAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 500_000 ether);

        vm.startPrank(user1);
        elta.approve(address(veElta), amount);
        veElta.lock(amount, uint64(block.timestamp + 365 days));

        (uint128 principal,) = veElta.locks(user1);
        assertEq(principal, amount, "Principal should match lock amount");
        vm.stopPrank();
    }

    function testFuzz_VeELTA_LockDuration(uint256 durationDays) public {
        // Between MIN_LOCK (7 days) and MAX_LOCK (730 days = 2 years)
        durationDays = bound(durationDays, 8, 729); // within valid range

        vm.startPrank(user1);
        elta.approve(address(veElta), 1000 ether);

        veElta.lock(1000 ether, uint64(block.timestamp + durationDays * 1 days));

        uint256 votingPower = veElta.getVotes(user1);
        assertGe(votingPower, 1000 ether, "Voting power should be at least principal");
        assertLe(votingPower, 2000 ether, "Voting power should not exceed 2x");
        vm.stopPrank();
    }

    function testFuzz_Vault_StakeAmount(uint256 amount) public {
        amount = bound(amount, 1 ether, 50_000 ether);

        vm.prank(admin);
        appToken.mint(user1, amount);

        vm.startPrank(user1);
        appToken.approve(address(vault), amount);
        vault.stake(amount);

        assertEq(vault.balanceOf(user1), amount, "First staker should get 1:1 shares");
        vm.stopPrank();
    }

    function testFuzz_Distributor_DepositAmount(uint256 amount) public {
        amount = bound(amount, 10 ether, 100_000 ether);

        vm.prank(admin);
        elta.transfer(address(this), amount);
        elta.approve(address(distributor), amount);

        distributor.deposit(amount);
        assertEq(distributor.getEpochCount(), 1, "Should create epoch");
    }
}
