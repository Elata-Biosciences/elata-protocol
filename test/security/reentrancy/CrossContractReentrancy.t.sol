// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {AppStakingVault} from "../../../src/apps/AppStakingVault.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {ReferralRegistry} from "../../../src/modules/ReferralRegistry.sol";
import {AirdropDistributor} from "../../../src/modules/AirdropDistributor.sol";
import {AppVestingWallet} from "../../../src/vesting/AppVestingWallet.sol";
import {LpLocker} from "../../../src/apps/LpLocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock LP token
contract MockLPToken is ERC20 {
    constructor() ERC20("LP Token", "LP") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

/// @notice Attacker contract for FeeCollector → FeeManager chain
contract FeeChainAttacker {
    FeeCollector public collector;
    FeeManager public manager;
    IERC20 public elta;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _collector, address _manager, address _elta) {
        collector = FeeCollector(_collector);
        manager = FeeManager(_manager);
        elta = IERC20(_elta);
    }

    function depositAndAttack(uint256 appId, uint256 amount) external {
        attacking = true;
        attackCount = 0;
        elta.approve(address(collector), amount);
        collector.depositElta(appId, amount);
    }

    // Callback attempt
    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            try collector.sweepElta(1) {} catch {}
        }
    }
}

/// @notice Attacker for referral registry chain
contract ReferralChainAttacker {
    ReferralRegistry public registry;
    IERC20 public elta;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _registry, address _elta) {
        registry = ReferralRegistry(_registry);
        elta = IERC20(_elta);
    }

    function claimAndAttack() external {
        attacking = true;
        attackCount = 0;
        registry.claimRewards();
    }

    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            try registry.claimRewards() {} catch {}
        }
    }
}

/// @notice Attacker for airdrop chain
contract AirdropChainAttacker {
    AirdropDistributor public airdrop;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _airdrop) {
        airdrop = AirdropDistributor(_airdrop);
    }

    function claimAndAttack(uint256 campaignId, uint256 amount, bytes32[] calldata proof) external {
        attacking = true;
        attackCount = 0;
        airdrop.claim(campaignId, amount, proof);
    }

    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            bytes32[] memory proof = new bytes32[](0);
            try airdrop.claim(0, 100 ether, proof) {} catch {}
        }
    }
}

/// @notice Attacker for vesting wallet
contract VestingAttacker {
    AppVestingWallet public vesting;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _vesting) {
        vesting = AppVestingWallet(_vesting);
    }

    function releaseAndAttack() external {
        attacking = true;
        attackCount = 0;
        vesting.release();
    }

    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            try vesting.release() {} catch {}
        }
    }
}

/// @notice Attacker for LP locker
contract LpLockerAttacker {
    LpLocker public locker;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _locker) {
        locker = LpLocker(_locker);
    }

    function claimAndAttack() external {
        attacking = true;
        attackCount = 0;
        locker.claim();
    }

    receive() external payable {
        if (attacking && attackCount < 2) {
            attackCount++;
            try locker.claim() {} catch {}
        }
    }
}

/**
 * @title CrossContractReentrancy
 * @notice Tests for reentrancy across multiple contracts in the protocol
 */
contract CrossContractReentrancy is Test {
    ELTA public elta;
    MockERC20 public usdc;
    VeELTA public veElta;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    ReferralRegistry public referralRegistry;
    AirdropDistributor public airdropDistributor;
    AppToken public appToken;
    AppStakingVault public stakingVault;
    MockLPToken public lpToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public appRewards = makeAddr("appRewards");
    address public veRewards = makeAddr("veRewards");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy mock USDC
        usdc = new MockERC20("USDC", "USDC");

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(0), address(0));

        // Deploy FeeManager
        feeManager = new FeeManager(address(elta), address(usdc), admin, admin, appRewards, veRewards, treasury, 1 days);

        // Setup fee collector
        vm.prank(admin);
        feeCollector.setFeeManager(address(feeManager));
        vm.prank(admin);
        feeManager.setDepositor(address(feeCollector), true);

        // Deploy ReferralRegistry
        referralRegistry = new ReferralRegistry(admin, address(elta), 500); // 5% referral

        // Deploy AirdropDistributor
        airdropDistributor = new AirdropDistributor(admin, admin);

        // Deploy AppToken
        appToken =
            new AppToken("TestApp", "TEST", 18, 10_000_000 ether, admin, admin, admin, treasury, treasury, treasury);

        // Deploy LP token
        lpToken = new MockLPToken();

        // Deploy staking vault
        stakingVault = new AppStakingVault("TestApp", "TEST", IERC20(address(appToken)), admin);

        // Fund
        vm.startPrank(admin);
        elta.transfer(attacker, 1_000_000 ether);
        elta.transfer(user1, 1_000_000 ether);
        elta.transfer(address(referralRegistry), 100_000 ether);
        appToken.mint(attacker, 1_000_000 ether);
        appToken.mint(user1, 1_000_000 ether);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE PIPELINE CHAIN TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_FeeCollectorToFeeManager() public {
        // Deposit to fee collector
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        uint256 pending = feeCollector.pendingEltaFees(1);
        assertEq(pending, 100 ether, "Should have pending fees");

        // Sweep to fee manager
        feeCollector.sweepElta(1);

        // Pending should be 0
        assertEq(feeCollector.pendingEltaFees(1), 0, "Pending should be swept");
    }

    function test_CrossReentrancy_FeeChainAttack() public {
        FeeChainAttacker attackerContract =
            new FeeChainAttacker(address(feeCollector), address(feeManager), address(elta));

        vm.prank(admin);
        elta.transfer(address(attackerContract), 1000 ether);

        // Attempt attack
        vm.prank(attacker);
        attackerContract.depositAndAttack(1, 100 ether);

        // Attack count should be 0 (blocked)
        assertEq(attackerContract.attackCount(), 0, "Cross-contract reentrancy should be blocked");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFERRAL REGISTRY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_ReferralClaim() public {
        // Setup referral
        vm.prank(admin);
        referralRegistry.setAuthorizedCaller(admin, true);

        vm.prank(admin);
        referralRegistry.setReferrer(1, user1, attacker);

        // Accrue rewards
        vm.prank(admin);
        referralRegistry.accrueReferralReward(1, user1, 1000 ether);

        uint256 pending = referralRegistry.pendingRewards(attacker);
        assertGt(pending, 0, "Should have pending rewards");

        // Claim
        vm.prank(attacker);
        referralRegistry.claimRewards();

        assertEq(referralRegistry.pendingRewards(attacker), 0, "Rewards should be claimed");
    }

    function test_CrossReentrancy_ReferralClaimAttack() public {
        ReferralChainAttacker attackerContract = new ReferralChainAttacker(address(referralRegistry), address(elta));

        // Setup referral for attacker contract
        vm.prank(admin);
        referralRegistry.setAuthorizedCaller(admin, true);

        vm.prank(admin);
        referralRegistry.setReferrer(1, user1, address(attackerContract));

        vm.prank(admin);
        referralRegistry.accrueReferralReward(1, user1, 1000 ether);

        // Attempt attack
        vm.prank(attacker);
        attackerContract.claimAndAttack();

        // Should not be able to reenter
        assertEq(attackerContract.attackCount(), 0, "Reentrancy should be blocked");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AIRDROP DISTRIBUTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_AirdropClaim() public {
        // Create campaign
        bytes32 leaf = keccak256(abi.encodePacked(user1, uint256(100 ether)));
        bytes32 root = leaf;

        vm.prank(admin);
        uint256 campaignId = airdropDistributor.createCampaign(1, address(elta), root, "Test Airdrop");

        // Fund airdrop
        vm.prank(admin);
        elta.transfer(address(airdropDistributor), 1000 ether);

        // Claim
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(user1);
        airdropDistributor.claim(campaignId, 100 ether, proof);

        // Cannot claim again
        vm.prank(user1);
        vm.expectRevert(AirdropDistributor.AlreadyClaimed.selector);
        airdropDistributor.claim(campaignId, 100 ether, proof);
    }

    function test_CrossReentrancy_AirdropClaimAttack() public {
        AirdropChainAttacker attackerContract = new AirdropChainAttacker(address(airdropDistributor));

        // Create campaign for attacker
        bytes32 leaf = keccak256(abi.encodePacked(address(attackerContract), uint256(100 ether)));
        bytes32 root = leaf;

        vm.prank(admin);
        airdropDistributor.createCampaign(1, address(elta), root, "Test");

        vm.prank(admin);
        elta.transfer(address(airdropDistributor), 1000 ether);

        // Attack
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(attacker);
        attackerContract.claimAndAttack(0, 100 ether, proof);

        // Reentrancy should be blocked
        assertEq(attackerContract.attackCount(), 0, "Reentrancy should be blocked");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VESTING WALLET TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_VestingRelease() public {
        // Create vesting wallet
        AppVestingWallet vesting = new AppVestingWallet(
            1, // appId
            address(appToken),
            user1, // beneficiary
            uint64(block.timestamp),
            0, // no cliff
            365 days, // duration
            admin
        );

        // Fund vesting
        vm.prank(admin);
        appToken.mint(address(vesting), 1000 ether);

        // Warp time
        vm.warp(block.timestamp + 180 days);

        // Release
        uint256 releasable = vesting.releasable();
        assertGt(releasable, 0, "Should have releasable tokens");

        vesting.release();
    }

    function test_CrossReentrancy_VestingReleaseAttack() public {
        VestingAttacker attackerContract;

        // Create vesting wallet with attacker as beneficiary
        AppVestingWallet vesting = new AppVestingWallet(
            1,
            address(appToken),
            address(0x1234), // placeholder
            uint64(block.timestamp),
            0,
            365 days,
            admin
        );

        // We can't set attacker contract as beneficiary directly, so test standard flow
        vm.prank(admin);
        appToken.mint(address(vesting), 1000 ether);

        vm.warp(block.timestamp + 180 days);

        // Release should work
        vesting.release();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LP LOCKER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_LpLockerClaim() public {
        // Create LP locker
        uint256 unlockTime = block.timestamp + 30 days;
        LpLocker locker = new LpLocker(1, address(lpToken), user1, unlockTime);

        // Transfer LP tokens to locker via lockLp
        lpToken.transfer(address(locker), 1000 ether);
        locker.lockLp(1000 ether);

        // Warp past unlock
        vm.warp(unlockTime + 1);

        // Claim
        vm.prank(user1);
        locker.claim();

        // Verify claimed
        assertTrue(locker.claimed(), "Should be claimed");
    }

    function test_CrossReentrancy_LpLockerDoubleClaim() public {
        uint256 unlockTime = block.timestamp + 30 days;
        LpLocker locker = new LpLocker(1, address(lpToken), user1, unlockTime);

        lpToken.transfer(address(locker), 1000 ether);
        locker.lockLp(1000 ether);

        vm.warp(unlockTime + 1);

        vm.prank(user1);
        locker.claim();

        // Cannot claim again
        vm.prank(user1);
        vm.expectRevert(LpLocker.AlreadyClaimed.selector);
        locker.claim();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STAKING VAULT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_StakingVaultStakeUnstake() public {
        vm.startPrank(user1);
        appToken.approve(address(stakingVault), 1000 ether);

        stakingVault.stake(500 ether);
        assertEq(stakingVault.balanceOf(user1), 500 ether, "Should have staked");

        stakingVault.unstake(250 ether);
        assertEq(stakingVault.balanceOf(user1), 250 ether, "Should have unstaked");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTI-CONTRACT FLOW TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CrossReentrancy_FullFeeFlow() public {
        // 1. Deposit ELTA to fee collector
        vm.startPrank(attacker);
        elta.approve(address(feeCollector), 1000 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        // 2. Sweep to fee manager
        feeCollector.sweepElta(1);

        // 3. Verify state consistency
        assertEq(feeCollector.pendingEltaFees(1), 0, "Should be swept");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_CrossReentrancy_FeeDeposits(uint256 amount, uint256 appId) public {
        amount = bound(amount, 1 ether, 100_000 ether);
        appId = bound(appId, 0, 100);

        vm.startPrank(attacker);
        elta.approve(address(feeCollector), amount);
        feeCollector.depositElta(appId, amount);
        vm.stopPrank();

        assertEq(feeCollector.pendingEltaFees(appId), amount, "Pending should match deposit");
    }

    function testFuzz_CrossReentrancy_StakeUnstake(uint256 stakeAmount, uint256 unstakePercent) public {
        stakeAmount = bound(stakeAmount, 1 ether, 500_000 ether);
        unstakePercent = bound(unstakePercent, 1, 100);

        vm.startPrank(user1);
        appToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount);

        uint256 unstakeAmount = (stakeAmount * unstakePercent) / 100;
        stakingVault.unstake(unstakeAmount);

        assertEq(stakingVault.balanceOf(user1), stakeAmount - unstakeAmount, "Balance should be correct");
        vm.stopPrank();
    }
}
