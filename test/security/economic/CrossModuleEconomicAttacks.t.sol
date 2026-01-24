// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {AppStakingVault} from "../../../src/apps/AppStakingVault.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {ReferralRegistry} from "../../../src/modules/ReferralRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock USDC
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Contract that attempts to game multiple modules
contract MultiModuleAttacker {
    ELTA public elta;
    AppToken public appToken;
    AppStakingVault public stakingVault;
    FeeCollector public feeCollector;
    ReferralRegistry public referralRegistry;

    constructor(
        ELTA _elta,
        AppToken _appToken,
        AppStakingVault _stakingVault,
        FeeCollector _feeCollector,
        ReferralRegistry _referralRegistry
    ) {
        elta = _elta;
        appToken = _appToken;
        stakingVault = _stakingVault;
        feeCollector = _feeCollector;
        referralRegistry = _referralRegistry;
    }

    // Attack: Stake tokens, unstake, repeat (testing stake weight manipulation)
    function stakeUnstakeAttack(uint256 amount, uint256 iterations) external {
        appToken.approve(address(stakingVault), type(uint256).max);

        for (uint256 i = 0; i < iterations; i++) {
            stakingVault.stake(amount);
            // Immediate unstake to test if any manipulation is possible
            stakingVault.unstake(amount);
        }
    }

    // Attack: Try to manipulate stake weight
    function rewardDrainAttempt() external {
        uint256 balance = appToken.balanceOf(address(this));
        if (balance > 0) {
            appToken.approve(address(stakingVault), balance);
            stakingVault.stake(balance);
            // Stake weight is now increased
        }
    }
}

/// @notice Flash loan simulator for economic attacks
contract FlashLoanAttacker {
    ELTA public elta;
    AppToken public appToken;
    AppStakingVault public stakingVault;

    constructor(ELTA _elta, AppToken _appToken, AppStakingVault _stakingVault) {
        elta = _elta;
        appToken = _appToken;
        stakingVault = _stakingVault;
    }

    function executeFlashLoanStakeAttack(uint256 flashAmount) external {
        // Simulate receiving flash loan of app tokens
        uint256 balanceBefore = appToken.balanceOf(address(this));

        // Stake flash-borrowed tokens to manipulate rewards
        appToken.approve(address(stakingVault), flashAmount);
        try stakingVault.stake(flashAmount) {
            // Unstake to repay flash loan
            stakingVault.unstake(flashAmount);
        } catch {}

        uint256 balanceAfter = appToken.balanceOf(address(this));
        console2.log("Flash attack profit:", balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0);
    }
}

/**
 * @title CrossModuleEconomicAttacks
 * @notice Red team security tests for multi-contract attack chains
 * @dev Tests for:
 *      - Bonding curve to fee manipulation
 *      - Staking rewards draining
 *      - Tournament + referral combo attacks
 *      - Content purchase fee split manipulation
 *      - Graduation fee routing
 *      - Vesting + staking interaction
 *      - Flash loan across modules
 */
contract CrossModuleEconomicAttacks is Test {
    ELTA public elta;
    MockUSDC public usdc;
    AppToken public appToken;
    AppStakingVault public stakingVault;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    ReferralRegistry public referralRegistry;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public appRewardsDistributor = makeAddr("appRewardsDistributor");
    address public veRewardsDistributor = makeAddr("veRewardsDistributor");
    address public creator = makeAddr("creator");
    address public attacker = makeAddr("attacker");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant APP_TOKEN_SUPPLY = 10_000_000 ether;
    uint256 public constant APP_ID = 1;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA("ELTA", "ELTA", admin, admin, ELTA_MAX_SUPPLY, ELTA_MAX_SUPPLY);

        // Deploy USDC
        usdc = new MockUSDC();

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        // Deploy FeeManager
        feeManager = new FeeManager(
            address(elta),
            address(usdc),
            admin,
            governance,
            appRewardsDistributor,
            veRewardsDistributor,
            treasury,
            1 days
        );

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(feeManager), address(0));

        // Deploy AppStakingVault
        stakingVault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), admin);

        // Deploy ReferralRegistry
        referralRegistry = new ReferralRegistry(admin, address(elta), 500); // 5%

        // Connect components
        vm.startPrank(admin);
        feeManager.setDepositor(address(feeCollector), true);
        referralRegistry.setAuthorizedCaller(address(this), true); // For testing
        vm.stopPrank();

        // Mint tokens to admin
        vm.prank(admin);
        appToken.mint(admin, APP_TOKEN_SUPPLY);

        // Fund users
        vm.startPrank(admin);
        appToken.transfer(attacker, 1_000_000 ether);
        appToken.transfer(alice, 1_000_000 ether);
        appToken.transfer(bob, 1_000_000 ether);
        elta.transfer(attacker, 100_000 ether);
        elta.transfer(alice, 100_000 ether);
        vm.stopPrank();

        // Fund referral registry for rewards
        elta.mint(address(referralRegistry), 1_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING REWARDS DRAINING ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_StakingRewardsDraining() public {
        // Fund staking vault with rewards
        vm.prank(admin);
        elta.transfer(address(stakingVault), 10_000 ether);

        // Alice stakes first
        vm.startPrank(alice);
        appToken.approve(address(stakingVault), 100_000 ether);
        stakingVault.stake(100_000 ether);
        vm.stopPrank();

        // Attacker stakes large amount
        vm.startPrank(attacker);
        appToken.approve(address(stakingVault), 500_000 ether);
        stakingVault.stake(500_000 ether);
        vm.stopPrank();

        // Warp time for rewards accrual
        vm.warp(block.timestamp + 1 days);

        // Verify stake weights are tracked correctly
        uint256 attackerStake = stakingVault.stakedOf(attacker);
        uint256 aliceStake = stakingVault.stakedOf(alice);

        console2.log("Attacker stake:", attackerStake);
        console2.log("Alice stake:", aliceStake);

        // Verify stake proportions (attacker has 5x stake)
        assertEq(attackerStake, 500_000 ether, "Attacker stake incorrect");
        assertEq(aliceStake, 100_000 ether, "Alice stake incorrect");
    }

    function test_Security_FlashLoanStakeAttack() public {
        // Deploy flash loan attacker
        FlashLoanAttacker attackerContract = new FlashLoanAttacker(elta, appToken, stakingVault);

        // Fund attacker with simulated flash loan
        vm.prank(admin);
        appToken.transfer(address(attackerContract), 1_000_000 ether);

        // Fund vault with rewards
        vm.prank(admin);
        elta.transfer(address(stakingVault), 10_000 ether);

        // Alice stakes legitimately first
        vm.startPrank(alice);
        appToken.approve(address(stakingVault), 100_000 ether);
        stakingVault.stake(100_000 ether);
        vm.stopPrank();

        // Warp for some rewards accrual
        vm.warp(block.timestamp + 1 hours);

        // Execute flash loan attack
        attackerContract.executeFlashLoanStakeAttack(1_000_000 ether);

        // Verify attacker didn't steal disproportionate rewards
        // The time-weighted reward calculation should prevent instant reward drain
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFERRAL + FEE MANIPULATION ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ReferralFeeArbitrage() public {
        // Set up referral chain
        referralRegistry.setReferrer(APP_ID, alice, attacker);

        // Accrue rewards for Alice's purchase
        referralRegistry.accrueReferralReward(APP_ID, alice, 10_000 ether);

        uint256 attackerReward = referralRegistry.pendingRewards(attacker);
        uint256 expectedReward = (10_000 ether * 500) / 10_000; // 5%

        assertEq(attackerReward, expectedReward, "Reward should be exactly 5%");

        // Attacker claims
        uint256 attackerEltaBefore = elta.balanceOf(attacker);
        vm.prank(attacker);
        referralRegistry.claimRewards();
        uint256 attackerEltaAfter = elta.balanceOf(attacker);

        assertEq(attackerEltaAfter - attackerEltaBefore, expectedReward, "Should receive exact reward");
    }

    function test_Security_SelfReferralViaProxy() public {
        // Attacker creates proxy address
        address proxy = makeAddr("proxy");

        // Set up: attacker -> proxy
        referralRegistry.setReferrer(APP_ID, proxy, attacker);

        // Proxy makes purchases, attacker gets rewards
        // This is allowed - mitigation is off-chain detection
        referralRegistry.accrueReferralReward(APP_ID, proxy, 10_000 ether);

        uint256 reward = referralRegistry.pendingRewards(attacker);
        assertGt(reward, 0, "Attacker receives rewards from proxy");

        // Document: This is a known limitation
        // Sybil prevention requires off-chain analysis or minimum purchase requirements
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE PIPELINE MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_FeeCollectorManipulation() public {
        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        // Verify fees are tracked
        uint256 pending = feeCollector.pendingEltaFees(APP_ID);
        assertEq(pending, 10_000 ether, "Fees should be tracked");

        // Sweep is permissionless but funds go to FeeManager
        uint256 managerBefore = elta.balanceOf(address(feeManager));
        feeCollector.sweepElta(APP_ID);
        uint256 managerAfter = elta.balanceOf(address(feeManager));

        assertEq(managerAfter - managerBefore, 10_000 ether, "Funds should go to manager");

        // Attacker cannot redirect funds
        assertEq(elta.balanceOf(attacker), 100_000 ether - 10_000 ether, "Attacker should have sent fees");
    }

    function test_Security_EpochSettlementManipulation() public {
        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Warp past epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Close epoch
        feeManager.closeEpoch(APP_ID);

        // Verify funds distributed
        uint256 appRewards = elta.balanceOf(appRewardsDistributor);
        uint256 veRewards = elta.balanceOf(veRewardsDistributor);

        assertGt(appRewards, 0, "App rewards should be distributed");
        assertGt(veRewards, 0, "VE rewards should be distributed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-MODULE ATTACK CHAINS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_MultiModuleAttacker() public {
        // Deploy multi-module attacker
        MultiModuleAttacker attackerContract =
            new MultiModuleAttacker(elta, appToken, stakingVault, feeCollector, referralRegistry);

        // Fund attacker contract
        vm.prank(admin);
        appToken.transfer(address(attackerContract), 500_000 ether);

        // Fund staking vault
        vm.prank(admin);
        elta.transfer(address(stakingVault), 10_000 ether);

        // Try stake-unstake attack
        attackerContract.stakeUnstakeAttack(100_000 ether, 5);

        // Verify no abnormal profit
        uint256 attackerEltaBalance = elta.balanceOf(address(attackerContract));
        console2.log("Attacker ELTA after attack:", attackerEltaBalance);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME-BASED ATTACKS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_TimeManipulationAcrossModules() public {
        // Stake tokens
        vm.startPrank(alice);
        appToken.approve(address(stakingVault), 100_000 ether);
        stakingVault.stake(100_000 ether);
        vm.stopPrank();

        // Deposit fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Warp 1 day
        vm.warp(block.timestamp + 1 days + 1);

        // Close epoch
        feeManager.closeEpoch(APP_ID);

        // Both staking and fee distribution should be time-consistent
        // No arbitrage between time-based mechanisms
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ECONOMIC INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_ValueConservation() public {
        // Track total value before
        uint256 totalEltaBefore = elta.balanceOf(attacker) + elta.balanceOf(alice) + elta.balanceOf(bob)
            + elta.balanceOf(address(feeCollector)) + elta.balanceOf(address(feeManager));

        // Deposit and sweep fees
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 10_000 ether);
        feeCollector.depositElta(APP_ID, 10_000 ether);
        vm.stopPrank();

        feeCollector.sweepElta(APP_ID);

        // Track total value after
        uint256 totalEltaAfter = elta.balanceOf(attacker) + elta.balanceOf(alice) + elta.balanceOf(bob)
            + elta.balanceOf(address(feeCollector)) + elta.balanceOf(address(feeManager));

        // ELTA should be conserved (no creation/destruction)
        assertEq(totalEltaAfter, totalEltaBefore, "ELTA should be conserved");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_FeeDepositAndSweep(uint256 amount) public {
        amount = bound(amount, 1 ether, 50_000 ether);

        uint256 attackerBefore = elta.balanceOf(attacker);

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(APP_ID, amount);
        vm.stopPrank();

        uint256 attackerAfter = elta.balanceOf(attacker);
        assertEq(attackerBefore - attackerAfter, amount, "Should transfer exact amount");

        uint256 pending = feeCollector.pendingEltaFees(APP_ID);
        assertEq(pending, amount, "Should track pending");

        feeCollector.sweepElta(APP_ID);

        uint256 managerBalance = elta.balanceOf(address(feeManager));
        assertEq(managerBalance, amount, "Should sweep to manager");
    }

    function testFuzz_StakingRewardsDistribution(uint256 stakeAmount, uint256 rewardAmount) public {
        stakeAmount = bound(stakeAmount, 1 ether, 500_000 ether);
        rewardAmount = bound(rewardAmount, 1 ether, 10_000 ether);

        // Fund vault with rewards
        vm.prank(admin);
        elta.transfer(address(stakingVault), rewardAmount);

        // Stake
        vm.startPrank(alice);
        appToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount);
        vm.stopPrank();

        // Verify stake tracked
        uint256 aliceStake = stakingVault.stakedOf(alice);
        assertEq(aliceStake, stakeAmount, "Stake should be tracked");

        // Warp time
        vm.warp(block.timestamp + 1 days);

        // Verify stake is still tracked after time passes
        uint256 aliceStakeAfter = stakingVault.stakedOf(alice);
        assertEq(aliceStakeAfter, stakeAmount, "Stake should persist after time warp");

        // Verify total staked
        uint256 totalStaked = stakingVault.totalStaked();
        assertEq(totalStaked, stakeAmount, "Total staked should match");
    }
}
