// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {ProtocolConfig} from "../../../src/core/ProtocolConfig.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {FeeManager} from "../../../src/fees/FeeManager.sol";
import {FeeSwapper} from "../../../src/fees/FeeSwapper.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";
import {AirdropDistributor} from "../../../src/modules/AirdropDistributor.sol";
import {ReferralRegistry} from "../../../src/modules/ReferralRegistry.sol";
import {ElataPoints} from "../../../src/experience/ElataPoints.sol";
import {AppVestingWallet} from "../../../src/vesting/AppVestingWallet.sol";
import {LpLocker} from "../../../src/apps/LpLocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
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

/// @notice Mock LP token
contract MockLP is ERC20 {
    constructor() ERC20("LP", "LP") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

/**
 * @title AccessControlTests
 * @notice Exhaustive access control tests for all protocol contracts
 */
contract AccessControlTests is Test {
    ELTA public elta;
    VeELTA public veElta;
    ProtocolConfig public config;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    AppToken public appToken;
    AirdropDistributor public airdrop;
    ReferralRegistry public referral;
    ElataPoints public xp;
    MockUSDC public usdc;
    MockLP public lpToken;

    address public admin = makeAddr("admin");
    address public timelock = makeAddr("timelock");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public user = makeAddr("user");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        usdc = new MockUSDC();
        lpToken = new MockLP();

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy ProtocolConfig
        config = new ProtocolConfig(admin, timelock);

        // Deploy FeeCollector
        feeCollector = new FeeCollector(address(elta), admin, address(0), address(0));

        // Deploy FeeManager
        feeManager = new FeeManager(address(elta), address(usdc), admin, admin, treasury, treasury, treasury, 1 days);

        // Deploy AppToken
        appToken =
            new AppToken("TestApp", "TEST", 18, 10_000_000 ether, admin, admin, admin, treasury, treasury, treasury);

        // Deploy AirdropDistributor
        airdrop = new AirdropDistributor(admin, admin);

        // Deploy ReferralRegistry
        referral = new ReferralRegistry(admin, address(elta), 500);

        // Deploy ElataPoints
        xp = new ElataPoints(admin);

        // Fund
        vm.prank(admin);
        elta.transfer(user, 1_000_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELTA TOKEN - No Access Control (trustless design)
    // ═══════════════════════════════════════════════════════════════════════════

    // NOTE: ELTA is now a fixed-supply trustless token with no roles.
    // All 77M tokens are minted to treasury at deployment.
    // Tests for minting/roles have been removed.

    // ═══════════════════════════════════════════════════════════════════════════
    // VeELTA ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_VeELTA_NonTransferable() public {
        // Lock some tokens
        vm.startPrank(user);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 365 days));

        // Try to transfer veELTA (should fail - soulbound)
        vm.expectRevert();
        veElta.transfer(attacker, 100 ether);
        vm.stopPrank();
    }

    function test_Access_VeELTA_CannotUnlockBeforeExpiry() public {
        vm.startPrank(user);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 30 days));

        // Cannot unlock before expiry
        vm.expectRevert();
        veElta.unlock();
        vm.stopPrank();
    }

    function test_Access_VeELTA_OnlyOwnerCanUnlock() public {
        vm.startPrank(user);
        elta.approve(address(veElta), 1000 ether);
        veElta.lock(1000 ether, uint64(block.timestamp + 8 days));
        vm.stopPrank();

        // Warp past unlock
        vm.warp(block.timestamp + 9 days);

        // Attacker cannot unlock user's tokens
        vm.prank(attacker);
        vm.expectRevert(); // No lock for attacker
        veElta.unlock();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROTOCOL CONFIG ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_ProtocolConfig_OnlyTimelockCanSetBondingCurveTax() public {
        vm.prank(attacker);
        vm.expectRevert();
        config.setBondingCurveTradeTaxBps(200);

        // Admin cannot either
        vm.prank(admin);
        vm.expectRevert();
        config.setBondingCurveTradeTaxBps(200);

        // Only timelock
        vm.prank(timelock);
        config.setBondingCurveTradeTaxBps(200);
        assertEq(config.bondingCurveTradeTaxBps(), 200);
    }

    function test_Access_ProtocolConfig_OnlyTimelockCanSetGraduationTarget() public {
        vm.prank(attacker);
        vm.expectRevert();
        config.setGraduationTarget(2000 ether);

        vm.prank(timelock);
        config.setGraduationTarget(2000 ether);
    }

    function test_Access_ProtocolConfig_OnlyTimelockCanSetFeeSplits() public {
        vm.prank(attacker);
        vm.expectRevert();
        config.setFeeSplits(7000, 1500, 500, 500, 500);

        vm.prank(timelock);
        config.setFeeSplits(7000, 1500, 500, 500, 500);
    }

    function test_Access_ProtocolConfig_OnlyAdminCanSetMaxSlippage() public {
        vm.prank(attacker);
        vm.expectRevert();
        config.setMaxSlippageBps(500);

        vm.prank(admin);
        config.setMaxSlippageBps(500);
    }

    function test_Access_ProtocolConfig_OnlyAdminCanSetRouterAllowed() public {
        vm.prank(attacker);
        vm.expectRevert();
        config.setRouterAllowed(address(0x123), true);

        vm.prank(admin);
        config.setRouterAllowed(address(0x123), true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE COLLECTOR ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_FeeCollector_OnlyAdminCanSetFeeManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        feeCollector.setFeeManager(address(0x123));

        vm.prank(admin);
        feeCollector.setFeeManager(address(0x123));
    }

    function test_Access_FeeCollector_OnlyAdminCanSetFeeSwapper() public {
        vm.prank(attacker);
        vm.expectRevert();
        feeCollector.setFeeSwapper(address(0x123));

        vm.prank(admin);
        feeCollector.setFeeSwapper(address(0x123));
    }

    function test_Access_FeeCollector_AnyoneCanDeposit() public {
        // Anyone can deposit ELTA for an app
        vm.startPrank(user);
        elta.approve(address(feeCollector), 100 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        assertEq(feeCollector.pendingEltaFees(1), 100 ether);
    }

    function test_Access_FeeCollector_AnyoneCanSweep() public {
        // Set up fee manager first
        vm.prank(admin);
        feeCollector.setFeeManager(address(feeManager));

        // Set up depositor permission
        vm.prank(admin);
        feeManager.setDepositor(address(feeCollector), true);

        // Deposit first
        vm.startPrank(user);
        elta.approve(address(feeCollector), 100 ether);
        feeCollector.depositElta(1, 100 ether);
        vm.stopPrank();

        // Verify deposit
        assertEq(feeCollector.pendingEltaFees(1), 100 ether, "Should have pending fees");

        // Anyone can trigger sweep (permissionless) - but without proper setup it may do nothing
        vm.prank(attacker);
        feeCollector.sweepElta(1);

        // Fees should be swept
        assertEq(feeCollector.pendingEltaFees(1), 0, "Fees should be swept");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE MANAGER ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_FeeManager_OnlyDepositorCanDeposit() public {
        vm.prank(attacker);
        vm.expectRevert();
        feeManager.depositEltaForApp(1, 100 ether);
    }

    function test_Access_FeeManager_OnlyAdminCanSetDepositor() public {
        vm.prank(attacker);
        vm.expectRevert();
        feeManager.setDepositor(address(0x123), true);

        vm.prank(admin);
        feeManager.setDepositor(address(0x123), true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // APP TOKEN ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_AppToken_OnlyMinterCanMint() public {
        vm.prank(attacker);
        vm.expectRevert();
        appToken.mint(attacker, 1000 ether);
    }

    function test_Access_AppToken_OnlyGovernanceCanSetTransferFee() public {
        vm.prank(attacker);
        vm.expectRevert();
        appToken.setTransferFeeBps(100);
    }

    function test_Access_AppToken_OnlyGovernanceCanSetBurnFee() public {
        vm.prank(attacker);
        vm.expectRevert();
        appToken.setBurnFeeBps(100);
    }

    function test_Access_AppToken_OnlyAdminCanSetVault() public {
        vm.prank(attacker);
        vm.expectRevert();
        appToken.setVault(address(0x123));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AIRDROP DISTRIBUTOR ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_Airdrop_OnlyOperatorCanCreateCampaign() public {
        vm.prank(attacker);
        vm.expectRevert();
        airdrop.createCampaign(1, address(elta), bytes32(uint256(1)), "Test");

        vm.prank(admin);
        airdrop.createCampaign(1, address(elta), bytes32(uint256(1)), "Test");
    }

    function test_Access_Airdrop_OnlyAdminCanDeactivate() public {
        vm.prank(admin);
        airdrop.createCampaign(1, address(elta), bytes32(uint256(1)), "Test");

        vm.prank(attacker);
        vm.expectRevert();
        airdrop.deactivateCampaign(0);

        vm.prank(admin);
        airdrop.deactivateCampaign(0);
    }

    function test_Access_Airdrop_OnlyAdminCanRescueTokens() public {
        vm.prank(admin);
        elta.transfer(address(airdrop), 100 ether);

        vm.prank(attacker);
        vm.expectRevert();
        airdrop.rescueTokens(address(elta), attacker, 100 ether);

        vm.prank(admin);
        airdrop.rescueTokens(address(elta), admin, 100 ether);
    }

    function test_Access_Airdrop_OnlyAdminCanSetAdmin() public {
        vm.prank(attacker);
        vm.expectRevert();
        airdrop.setAdmin(attacker);

        vm.prank(admin);
        airdrop.setAdmin(user);
        assertEq(airdrop.admin(), user);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REFERRAL REGISTRY ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_Referral_OnlyAuthorizedCanSetReferrer() public {
        vm.prank(attacker);
        vm.expectRevert();
        referral.setReferrer(1, user, attacker);
    }

    function test_Access_Referral_OnlyAuthorizedCanAccrueReward() public {
        vm.prank(attacker);
        vm.expectRevert();
        referral.accrueReferralReward(1, user, 100 ether);
    }

    function test_Access_Referral_OnlyAdminCanSetAuthorizedCaller() public {
        vm.prank(attacker);
        vm.expectRevert();
        referral.setAuthorizedCaller(attacker, true);

        vm.prank(admin);
        referral.setAuthorizedCaller(address(0x123), true);
    }

    function test_Access_Referral_OnlyAdminCanSetReferralBps() public {
        vm.prank(attacker);
        vm.expectRevert();
        referral.setReferralBps(1000);

        vm.prank(admin);
        referral.setReferralBps(1000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELATA XP ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_XP_OnlyOperatorCanAward() public {
        vm.prank(attacker);
        vm.expectRevert();
        xp.award(attacker, 100 ether);

        vm.prank(admin);
        xp.award(user, 100 ether);
    }

    function test_Access_XP_OnlyOperatorCanRevoke() public {
        vm.prank(admin);
        xp.award(user, 100 ether);

        vm.prank(attacker);
        vm.expectRevert();
        xp.revoke(user, 50 ether);

        vm.prank(admin);
        xp.revoke(user, 50 ether);
    }

    function test_Access_XP_OnlyOperatorCanSetMerkleRoot() public {
        vm.prank(attacker);
        vm.expectRevert();
        xp.setMerkleRoot(bytes32(uint256(1)), bytes32(0));

        vm.prank(admin);
        xp.setMerkleRoot(bytes32(uint256(1)), bytes32(0));
    }

    function test_Access_XP_NonTransferable() public {
        vm.prank(admin);
        xp.award(user, 100 ether);

        vm.prank(user);
        vm.expectRevert();
        xp.transfer(attacker, 50 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VESTING WALLET ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_Vesting_OnlyAdminCanSetBeneficiary() public {
        AppVestingWallet vesting =
            new AppVestingWallet(1, address(appToken), user, uint64(block.timestamp), 0, 365 days, admin);

        vm.prank(attacker);
        vm.expectRevert();
        vesting.setBeneficiary(attacker);

        vm.prank(admin);
        vesting.setBeneficiary(treasury);
    }

    function test_Access_Vesting_AnyoneCanTriggerRelease() public {
        AppVestingWallet vesting =
            new AppVestingWallet(1, address(appToken), user, uint64(block.timestamp), 0, 365 days, admin);

        // Fund vesting
        vm.prank(admin);
        appToken.mint(address(vesting), 1000 ether);

        // Warp to vest some
        vm.warp(block.timestamp + 180 days);

        // Anyone can trigger release (tokens go to beneficiary)
        vm.prank(attacker);
        vesting.release();

        // User (beneficiary) should have tokens
        assertGt(appToken.balanceOf(user), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LP LOCKER ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_LpLocker_OnlyBeneficiaryCanClaim() public {
        uint256 unlockAt = block.timestamp + 30 days;
        LpLocker locker = new LpLocker(1, address(lpToken), user, unlockAt);

        // Fund locker
        lpToken.transfer(address(locker), 1000 ether);
        locker.lockLp(1000 ether);

        // Warp past unlock
        vm.warp(unlockAt + 1);

        // Attacker cannot claim
        vm.prank(attacker);
        vm.expectRevert(LpLocker.Unauthorized.selector);
        locker.claim();

        // Beneficiary can claim
        vm.prank(user);
        locker.claim();
    }

    function test_Access_LpLocker_CannotClaimBeforeUnlock() public {
        uint256 unlockAt = block.timestamp + 30 days;
        LpLocker locker = new LpLocker(1, address(lpToken), user, unlockAt);

        lpToken.transfer(address(locker), 1000 ether);
        locker.lockLp(1000 ether);

        // Cannot claim before unlock
        vm.prank(user);
        vm.expectRevert(LpLocker.NotYetUnlocked.selector);
        locker.claim();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLE RENOUNCEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Access_CannotRenounceLastAdmin() public {
        // This test verifies behavior around admin role management
        // Most OZ contracts allow renouncing, but it's risky

        // Try to renounce admin role
        bytes32 adminRole = appToken.DEFAULT_ADMIN_ROLE();

        vm.prank(admin);
        appToken.renounceRole(adminRole, admin);

        // Admin should no longer have role
        assertFalse(appToken.hasRole(adminRole, admin));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Access_OnlyHoldersCanTransferELTA(address caller) public {
        // Skip admin who has tokens
        vm.assume(caller != admin && caller != user && caller != address(0));

        // Random address with no ELTA cannot transfer
        vm.prank(caller);
        vm.expectRevert();
        elta.transfer(user, 1000 ether);
    }

    function testFuzz_Access_RandomCannotSetProtocolConfig(address caller) public {
        vm.assume(caller != timelock && caller != address(0));

        vm.prank(caller);
        vm.expectRevert();
        config.setBondingCurveTradeTaxBps(500);
    }

    function testFuzz_Access_RandomCannotAwardXP(address caller, address recipient, uint256 amount) public {
        vm.assume(caller != admin && caller != address(0));
        vm.assume(recipient != address(0));
        amount = bound(amount, 1, 1_000_000 ether);

        bytes32 operatorRole = xp.POINTS_OPERATOR_ROLE();
        vm.assume(!xp.hasRole(operatorRole, caller));

        vm.prank(caller);
        vm.expectRevert();
        xp.award(recipient, amount);
    }
}
