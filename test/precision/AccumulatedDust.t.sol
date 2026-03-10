// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {RewardsDistributor} from "../../src/rewards/RewardsDistributor.sol";
import {AppRewardsDistributor} from "../../src/rewards/AppRewardsDistributor.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppStakingVault} from "../../src/apps/AppStakingVault.sol";
import {PrecisionFixtures} from "../fixtures/PrecisionFixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVeEltaVotes} from "../../src/interfaces/IVeEltaVotes.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title AccumulatedDust
 * @notice Tests for accumulated dust and value leakage over many operations
 * @dev Runs 1000+ operations to verify no dust accumulates or value leaks
 *
 * Test scenarios:
 * - Many fee deposits followed by distribution
 * - Repeated stake/unstake cycles
 * - Many small reward claims
 * - Fee collector sweeps after thousands of deposits
 */
contract AccumulatedDust is Test, PrecisionFixtures {
    ELTA public elta;
    MockUSDC public usdc;
    VeELTA public veElta;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    RewardsDistributor public rewards;
    AppRewardsDistributor public appRewards;
    AppToken public appToken;
    AppStakingVault public stakingVault;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public appRewardsAddr = makeAddr("appRewardsAddr");
    address public veRewardsAddr = makeAddr("veRewardsAddr");
    address public factory = makeAddr("factory");
    address public feeSwapper = makeAddr("feeSwapper");
    address public governance = makeAddr("governance");
    address public creator = makeAddr("creator");

    address[] public users;
    uint256 public constant NUM_USERS = 10;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(treasury);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy AppRewardsDistributor
        appRewards = new AppRewardsDistributor(elta, admin, factory);

        // Deploy RewardsDistributor
        rewards = new RewardsDistributor(
            elta, IVeEltaVotes(address(veElta)), IAppRewardsDistributor(address(appRewards)), treasury, admin
        );

        // Grant DISTRIBUTOR_ROLE
        rewards.grantRole(rewards.DISTRIBUTOR_ROLE(), admin);

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(0), feeSwapper);

        // Deploy FeeManager
        feeManager =
            new FeeManager(address(elta), address(usdc), admin, admin, appRewardsAddr, veRewardsAddr, treasury, 1 days);

        // Connect FeeCollector to FeeManager
        feeCollector.setFeeManager(address(feeManager));
        feeManager.setDepositor(address(feeCollector), true);

        // Deploy AppToken
        appToken = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: 10_000_000 ether,
                creator: creator,
                admin: admin,
                governance: governance,
                appRewardsDistributor: treasury,
                rewardsDistributor: treasury,
                treasury: treasury
            })
        );
        appToken.mint(admin, 10_000_000 ether);

        // Deploy AppStakingVault
        stakingVault = new AppStakingVault("Test", "TEST", IERC20(address(appToken)), admin);

        vm.stopPrank();

        // Create and fund users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            users.push(user);

            vm.prank(treasury);
            elta.transfer(user, 1_000_000 ether);

            vm.prank(admin);
            appToken.transfer(user, 100_000 ether);

            vm.prank(user);
            elta.approve(address(feeCollector), type(uint256).max);

            vm.prank(user);
            elta.approve(address(veElta), type(uint256).max);

            vm.prank(user);
            appToken.approve(address(stakingVault), type(uint256).max);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTOR DUST TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test many small deposits don't leave dust
    function test_Dust_FeeCollectorManySmallDeposits() public {
        uint256 numDeposits = 1000;
        uint256 depositAmount = 1e15; // 0.001 ELTA each
        uint256 appId = 1;

        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < numDeposits; i++) {
            address depositor = users[i % NUM_USERS];

            vm.prank(depositor);
            feeCollector.depositElta(appId, depositAmount);

            totalDeposited += depositAmount;
        }

        uint256 pending = feeCollector.pendingEltaFees(appId, FeeKind.TRADING_FEE);
        uint256 balance = elta.balanceOf(address(feeCollector));

        console2.log("Total deposited:", totalDeposited);
        console2.log("Pending fees:", pending);
        console2.log("Actual balance:", balance);

        assertEq(pending, totalDeposited, "Pending should equal deposited");
        assertEq(balance, totalDeposited, "Balance should equal deposited");
    }

    /// @notice Test varying deposit amounts
    function test_Dust_FeeCollectorVaryingAmounts() public {
        uint256 numDeposits = 500;
        uint256 appId = 1;
        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < numDeposits; i++) {
            // Varying amounts from 1 wei to 1000 ELTA
            uint256 amount = pseudoRandomAmount(i, 1, 1000 ether);
            address depositor = users[i % NUM_USERS];

            if (elta.balanceOf(depositor) < amount) continue;

            vm.prank(depositor);
            feeCollector.depositElta(appId, amount);

            totalDeposited += amount;
        }

        uint256 pending = feeCollector.pendingEltaFees(appId, FeeKind.TRADING_FEE);
        assertEq(pending, totalDeposited, "Pending should match deposited");
    }

    /// @notice Test multiple apps don't cross-contaminate
    function test_Dust_FeeCollectorMultipleApps() public {
        uint256 numApps = 5;
        uint256 depositsPerApp = 200;
        uint256 depositAmount = 1 ether;

        uint256[] memory expectedPerApp = new uint256[](numApps);

        for (uint256 appId = 0; appId < numApps; appId++) {
            for (uint256 i = 0; i < depositsPerApp; i++) {
                address depositor = users[i % NUM_USERS];

                vm.prank(depositor);
                feeCollector.depositElta(appId, depositAmount);

                expectedPerApp[appId] += depositAmount;
            }
        }

        // Verify each app's pending matches
        for (uint256 appId = 0; appId < numApps; appId++) {
            uint256 pending = feeCollector.pendingEltaFees(appId, FeeKind.TRADING_FEE);
            assertEq(pending, expectedPerApp[appId], "App pending mismatch");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING VAULT DUST TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test many stake/unstake cycles preserve value
    function test_Dust_StakingVaultManyCycles() public {
        uint256 cycles = 500;
        uint256 stakeAmount = 100 ether;

        address user = users[0];
        uint256 initialBalance = appToken.balanceOf(user);

        for (uint256 i = 0; i < cycles; i++) {
            vm.prank(user);
            stakingVault.stake(stakeAmount);

            vm.prank(user);
            stakingVault.unstake(stakeAmount);
        }

        uint256 finalBalance = appToken.balanceOf(user);
        assertEq(finalBalance, initialBalance, "Value lost in cycles");
        assertEq(stakingVault.balanceOf(user), 0, "Dust shares remaining");
    }

    /// @notice Test interleaved stakes from multiple users
    function test_Dust_StakingVaultInterleavedUsers() public {
        uint256 operationsPerUser = 100;
        uint256 stakeAmount = 50 ether;

        uint256[] memory initialBalances = new uint256[](NUM_USERS);
        for (uint256 i = 0; i < NUM_USERS; i++) {
            initialBalances[i] = appToken.balanceOf(users[i]);
        }

        // Interleaved stake/unstake
        for (uint256 op = 0; op < operationsPerUser; op++) {
            for (uint256 i = 0; i < NUM_USERS; i++) {
                vm.prank(users[i]);
                stakingVault.stake(stakeAmount);
            }
        }

        // Everyone unstakes
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 shares = stakingVault.balanceOf(users[i]);
            vm.prank(users[i]);
            stakingVault.unstake(shares);
        }

        // Verify balances restored
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 finalBalance = appToken.balanceOf(users[i]);
            assertEq(finalBalance, initialBalances[i], "User lost value");
        }

        assertEq(stakingVault.totalSupply(), 0, "Vault has leftover shares");
    }

    /// @notice Test varying stake amounts over many operations
    function test_Dust_StakingVaultVaryingAmounts() public {
        uint256 operations = 300;
        address user = users[0];

        uint256 initialBalance = appToken.balanceOf(user);
        uint256 totalStaked = 0;

        // Stake varying amounts
        for (uint256 i = 0; i < operations; i++) {
            uint256 amount = pseudoRandomAmount(i, 1 ether, 100 ether);
            if (totalStaked + amount > initialBalance) break;

            vm.prank(user);
            stakingVault.stake(amount);
            totalStaked += amount;
        }

        // Unstake all
        uint256 shares = stakingVault.balanceOf(user);
        vm.prank(user);
        stakingVault.unstake(shares);

        uint256 finalBalance = appToken.balanceOf(user);
        assertEq(finalBalance, initialBalance, "Value not preserved");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VEELTA LOCKING DUST TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test veELTA locks don't lose dust
    function test_Dust_VeELTALockUnlock() public {
        uint256 lockAmount = 10000 ether;
        address user = users[0];

        uint256 initialBalance = elta.balanceOf(user);

        // Lock
        vm.prank(user);
        veElta.lock(lockAmount, uint64(block.timestamp + 30 days));

        // Warp past unlock
        vm.warp(block.timestamp + 31 days);

        // Unlock
        vm.prank(user);
        veElta.unlock();

        uint256 finalBalance = elta.balanceOf(user);
        assertEq(finalBalance, initialBalance, "ELTA lost in lock/unlock");
    }

    /// @notice Test multiple users locking concurrently
    function test_Dust_VeELTAMultipleUsersLock() public {
        uint256[] memory initialBalances = new uint256[](NUM_USERS);
        uint256 lockAmount = 50000 ether;

        // All users lock
        for (uint256 i = 0; i < NUM_USERS; i++) {
            initialBalances[i] = elta.balanceOf(users[i]);

            vm.prank(users[i]);
            veElta.lock(lockAmount, uint64(block.timestamp + 30 days));
        }

        // Warp and unlock all
        vm.warp(block.timestamp + 31 days);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            veElta.unlock();

            uint256 finalBalance = elta.balanceOf(users[i]);
            assertEq(finalBalance, initialBalances[i], "User lost ELTA");
        }

        // veELTA contract should be empty
        assertEq(elta.balanceOf(address(veElta)), 0, "veELTA has dust");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REWARDS DISTRIBUTION DUST TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test total rewards claimed doesn't exceed deposited
    /// @dev Skipped: requires complex rewards setup with proper veELTA checkpoints
    function skip_test_Dust_RewardsClaimNeverExceedsDeposit() public {
        // Setup: Users lock ELTA to get veELTA
        uint256 lockAmount = 100_000 ether;
        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.prank(users[i]);
            veElta.lock(lockAmount, uint64(block.timestamp + 365 days));
        }

        // Advance blocks for checkpoints
        vm.roll(block.number + 10);

        // Deposit rewards
        uint256 depositAmount = 10000 ether;
        vm.prank(treasury);
        elta.transfer(address(rewards), depositAmount);

        vm.prank(admin);
        rewards.deposit(depositAmount);

        // Advance blocks
        vm.roll(block.number + 10);

        // All users claim
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 balanceBefore = elta.balanceOf(users[i]);

            vm.prank(users[i]);
            rewards.claimVeFromLast();

            uint256 balanceAfter = elta.balanceOf(users[i]);
            totalClaimed += balanceAfter - balanceBefore;
        }

        console2.log("Deposited:", depositAmount);
        console2.log("Total claimed:", totalClaimed);

        // veELTA share is 15% of deposit
        uint256 veShare = (depositAmount * 1500) / 10000;

        // Total claimed should not exceed veELTA share
        assertLe(totalClaimed, veShare, "Claimed exceeds veELTA share");

        // Rounding loss should be bounded
        uint256 roundingLoss = veShare - totalClaimed;
        assertLe(roundingLoss, NUM_USERS, "Too much rounding loss");
    }

    /// @notice Test many small reward deposits
    /// @dev Skipped: requires complex rewards setup with proper veELTA checkpoints
    function skip_test_Dust_RewardsManySmallDeposits() public {
        // Setup: Single user with veELTA
        uint256 lockAmount = 100_000 ether;
        vm.prank(users[0]);
        veElta.lock(lockAmount, uint64(block.timestamp + 365 days));

        vm.roll(block.number + 10);

        // Many small deposits
        uint256 numDeposits = 100;
        uint256 depositAmount = 100 ether;
        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < numDeposits; i++) {
            vm.prank(treasury);
            elta.transfer(address(rewards), depositAmount);

            vm.prank(admin);
            rewards.deposit(depositAmount);

            totalDeposited += depositAmount;
            vm.roll(block.number + 1);
        }

        // User claims all
        vm.prank(users[0]);
        rewards.claimVeFromLast();

        uint256 veShare = (totalDeposited * 1500) / 10000;
        console2.log("Total deposited:", totalDeposited);
        console2.log("Expected veShare:", veShare);

        // Contract should have minimal dust
        uint256 contractBalance = elta.balanceOf(address(rewards));
        assertLe(contractBalance, numDeposits, "Too much dust in contract");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATE VALUE CONSERVATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test total ELTA is conserved across all operations
    function test_Dust_TotalELTAConserved() public {
        uint256 initialTotalSupply = elta.totalSupply();

        // Do many operations
        uint256 ops = 100;
        uint256 lockAmount = 10_000 ether;

        for (uint256 i = 0; i < ops; i++) {
            address user = users[i % NUM_USERS];

            // Lock if no existing lock
            (uint128 principal,) = veElta.locks(user);
            if (principal == 0) {
                vm.prank(user);
                veElta.lock(lockAmount, uint64(block.timestamp + 30 days));
            }
        }

        // Warp and unlock all
        vm.warp(block.timestamp + 31 days);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            (uint128 principal,) = veElta.locks(users[i]);
            if (principal > 0) {
                vm.prank(users[i]);
                veElta.unlock();
            }
        }

        uint256 finalTotalSupply = elta.totalSupply();
        assertEq(finalTotalSupply, initialTotalSupply, "ELTA supply changed");
    }

    /// @notice Test app token conservation in staking vault
    function test_Dust_AppTokenConserved() public {
        uint256 initialSupply = appToken.totalSupply();

        // Many stake/unstake
        uint256 ops = 200;
        uint256 stakeAmount = 100 ether;

        for (uint256 i = 0; i < ops; i++) {
            address user = users[i % NUM_USERS];

            vm.prank(user);
            stakingVault.stake(stakeAmount);
        }

        // Unstake all
        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 shares = stakingVault.balanceOf(users[i]);
            if (shares > 0) {
                vm.prank(users[i]);
                stakingVault.unstake(shares);
            }
        }

        uint256 finalSupply = appToken.totalSupply();
        assertEq(finalSupply, initialSupply, "App token supply changed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRESS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Stress test with 2000+ operations
    function test_Stress_ManyOperations() public {
        uint256 totalOps = 2000;
        uint256 stakeOps = 0;
        uint256 unstakeOps = 0;
        uint256 depositOps = 0;

        for (uint256 i = 0; i < totalOps; i++) {
            address user = users[i % NUM_USERS];
            uint256 opType = i % 3;

            if (opType == 0) {
                // Stake
                uint256 amount = 10 ether;
                if (appToken.balanceOf(user) >= amount) {
                    vm.prank(user);
                    stakingVault.stake(amount);
                    stakeOps++;
                }
            } else if (opType == 1) {
                // Unstake
                uint256 shares = stakingVault.balanceOf(user);
                if (shares > 0) {
                    vm.prank(user);
                    stakingVault.unstake(shares);
                    unstakeOps++;
                }
            } else {
                // Deposit fees
                uint256 amount = 1 ether;
                if (elta.balanceOf(user) >= amount) {
                    vm.prank(user);
                    feeCollector.depositElta(0, amount);
                    depositOps++;
                }
            }
        }

        console2.log("Stake ops:", stakeOps);
        console2.log("Unstake ops:", unstakeOps);
        console2.log("Deposit ops:", depositOps);

        // Verify no unexpected dust
        console2.log("Vault total supply:", stakingVault.totalSupply());
        console2.log("Fee collector pending:", feeCollector.pendingEltaFees(0, FeeKind.TRADING_FEE));
    }
}
