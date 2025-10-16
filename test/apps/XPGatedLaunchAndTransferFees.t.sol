// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { ElataXP } from "../../src/experience/ElataXP.sol";
import { AppFactory } from "../../src/apps/AppFactory.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppBondingCurve } from "../../src/apps/AppBondingCurve.sol";
import { AppStakingVault } from "../../src/apps/AppStakingVault.sol";
import { AppRewardsDistributor } from "../../src/rewards/AppRewardsDistributor.sol";
import { RewardsDistributor } from "../../src/rewards/RewardsDistributor.sol";
import { AppFeeRouter } from "../../src/fees/AppFeeRouter.sol";
import { VeELTA } from "../../src/staking/VeELTA.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";
import { IRewardsDistributor } from "../../src/interfaces/IRewardsDistributor.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import { IAppFeeRouter } from "../../src/interfaces/IAppFeeRouter.sol";
import { IElataXP } from "../../src/interfaces/IElataXP.sol";
import { IVeEltaVotes } from "../../src/interfaces/IVeEltaVotes.sol";
import { MockElataXP } from "../mocks/MockContracts.sol";

/**
 * @title XP-Gated Launch and Transfer Fees Test
 * @notice Comprehensive tests for the new protocol features:
 *         - XP-gated launch windows (early access for experienced users)
 *         - Fee-on-transfer mechanism for app tokens (1% default, 70/15/15 split)
 *         - Multi-token rewards distribution
 *         - Governance controls and view functions
 */
contract XPGatedLaunchAndTransferFeesTest is Test {
    ELTA public elta;
    ElataXP public xp;
    VeELTA public veELTA;
    RewardsDistributor public rewardsDistributor;
    AppRewardsDistributor public appRewardsDistributor;
    AppFeeRouter public appFeeRouter;
    AppFactory public factory;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public governance = makeAddr("governance");
    address public creator = makeAddr("creator");
    address public xpUser = makeAddr("xpUser");
    address public noXpUser = makeAddr("noXpUser");
    address public staker1 = makeAddr("staker1");
    address public staker2 = makeAddr("staker2");
    address public veHolder = makeAddr("veHolder");

    address public mockRouter = makeAddr("mockRouter");
    address public mockFactory = makeAddr("mockFactory");

    event XPGateUpdated(uint256 minXP, uint256 duration);
    event TransferFeeUpdated(uint16 oldBps, uint16 newBps);
    event TransferFeeExemptSet(address indexed account, bool exempt);
    event TransferFeeCollected(
        address indexed from,
        address indexed to,
        uint256 totalFee,
        uint256 appFee,
        uint256 veFee,
        uint256 treasuryFee
    );

    function setUp() public {
        // Deploy core contracts
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);

        xp = new ElataXP(admin);

        // Deploy VeELTA
        veELTA = new VeELTA(elta, governance);

        // Deploy app rewards first (will update factory later)
        appRewardsDistributor = new AppRewardsDistributor(elta, governance, address(1));

        // Deploy rewards distributors (needs appRewardsDistributor)
        rewardsDistributor = new RewardsDistributor(
            elta,
            IVeEltaVotes(address(veELTA)),
            IAppRewardsDistributor(address(appRewardsDistributor)),
            treasury,
            governance
        );

        // Deploy fee router
        appFeeRouter =
            new AppFeeRouter(elta, IRewardsDistributor(address(rewardsDistributor)), governance);

        // Setup mock Uniswap
        _setupMockUniswap();

        // Deploy AppFactory with interface casts
        factory = new AppFactory(
            elta,
            IUniswapV2Router02(mockRouter),
            treasury,
            IAppFeeRouter(address(appFeeRouter)),
            IAppRewardsDistributor(address(appRewardsDistributor)),
            IRewardsDistributor(address(rewardsDistributor)),
            IElataXP(address(xp)),
            governance,
            admin
        );

        // Grant factory role to the actual factory
        vm.startPrank(governance);
        appRewardsDistributor.grantRole(appRewardsDistributor.FACTORY_ROLE(), address(factory));
        vm.stopPrank();

        // Distribute ELTA
        vm.startPrank(treasury);
        elta.transfer(creator, 10_000 ether);
        elta.transfer(xpUser, 10_000 ether);
        elta.transfer(noXpUser, 10_000 ether);
        elta.transfer(staker1, 50_000 ether);
        elta.transfer(staker2, 50_000 ether);
        elta.transfer(veHolder, 100_000 ether);
        vm.stopPrank();

        // Award XP to xpUser (100 XP)
        vm.prank(admin);
        xp.award(xpUser, 100 ether);
    }

    function _setupMockUniswap() internal {
        vm.mockCall(mockRouter, abi.encodeWithSignature("factory()"), abi.encode(mockFactory));
        vm.mockCall(
            mockFactory, abi.encodeWithSignature("getPair(address,address)"), abi.encode(address(0))
        );
        vm.mockCall(
            mockFactory,
            abi.encodeWithSignature("createPair(address,address)"),
            abi.encode(address(1))
        );
        vm.mockCall(
            mockRouter,
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)"
            ),
            abi.encode(0, 0, 0)
        );
    }

    // ===== XP-Gated Launch Window Tests =====

    function test_XPGate_UserWithXPCanBuyDuringEarlyAccess() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("XPGatedApp", "XPG", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // User with XP can buy immediately
        uint256 purchaseAmount = 1000 ether;

        vm.startPrank(xpUser);
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        uint256 tokensOut = curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        assertGt(tokensOut, 0);
        assertTrue(curve.canUserBuy(xpUser));
    }

    function test_XPGate_UserWithoutXPCannotBuyDuringEarlyAccess() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("XPGatedApp", "XPG", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // User without XP cannot buy during early access
        uint256 purchaseAmount = 1000 ether;

        vm.startPrank(noXpUser);
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        vm.expectRevert(AppBondingCurve.InsufficientXP.selector);
        curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        assertFalse(curve.canUserBuy(noXpUser));
    }

    function test_XPGate_AllUsersCanBuyAfterEarlyAccessEnds() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("XPGatedApp", "XPG", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Fast forward past early access period (6 hours default)
        vm.warp(block.timestamp + 6 hours + 1);

        // Now user without XP can buy
        uint256 purchaseAmount = 1000 ether;

        vm.startPrank(noXpUser);
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        uint256 tokensOut = curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        assertGt(tokensOut, 0);
        assertTrue(curve.canUserBuy(noXpUser));
    }

    function test_XPGate_GovernanceCanUpdateParameters() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("XPGatedApp", "XPG", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Governance can update XP gate parameters
        uint256 newMinXP = 200 ether;
        uint256 newDuration = 12 hours;

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit XPGateUpdated(newMinXP, newDuration);
        curve.setXPGate(newMinXP, newDuration);

        (,, uint256 xpMin, bool isActive) = curve.getEarlyAccessInfo();
        assertEq(xpMin, newMinXP);
        assertTrue(isActive);
    }

    function test_XPGate_NonGovernanceCannotUpdateParameters() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("XPGatedApp", "XPG", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Non-governance cannot update
        vm.prank(creator);
        vm.expectRevert(AppBondingCurve.OnlyGovernance.selector);
        curve.setXPGate(200 ether, 12 hours);
    }

    // ===== Fee-on-Transfer Tests =====

    function test_FoT_TransferFeeAppliedCorrectly() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FoTApp", "FOT", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Buy some tokens
        uint256 purchaseAmount = 1000 ether;

        vm.startPrank(xpUser);
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        uint256 tokensOut = curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        // Transfer tokens - should apply 1% fee
        uint256 transferAmount = 1000 ether;
        address recipient = makeAddr("recipient");

        vm.prank(xpUser);
        token.transfer(recipient, transferAmount);

        // Recipient should receive 99% (1% fee)
        uint256 expectedNet = transferAmount * 99 / 100;
        assertEq(token.balanceOf(recipient), expectedNet);
    }

    function test_FoT_FeesSplitCorrectly() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FoTApp", "FOT", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Buy tokens
        uint256 purchaseAmount = 1000 ether;

        vm.startPrank(xpUser);
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        uint256 tokensOut = curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        // Get distributor balances before
        address appRewards = token.appRewardsDistributor();
        address veRewards = token.rewardsDistributor();
        address treasuryAddr = token.treasury();

        uint256 appRewardsBefore = token.balanceOf(appRewards);
        uint256 veRewardsBefore = token.balanceOf(veRewards);
        uint256 treasuryBefore = token.balanceOf(treasuryAddr);

        // Transfer 10000 tokens
        uint256 transferAmount = 10000 ether;
        address recipient = makeAddr("recipient");

        vm.prank(xpUser);
        token.transfer(recipient, transferAmount);

        // Check fee split: 1% fee = 100 tokens
        // 70% = 70, 15% = 15, 15% = 15
        uint256 expectedAppFee = 70 ether;
        uint256 expectedVeFee = 15 ether;
        uint256 expectedTreasuryFee = 15 ether;

        assertEq(token.balanceOf(appRewards) - appRewardsBefore, expectedAppFee);
        assertEq(token.balanceOf(veRewards) - veRewardsBefore, expectedVeFee);
        assertEq(token.balanceOf(treasuryAddr) - treasuryBefore, expectedTreasuryFee);
    }

    function test_FoT_ExemptAddressesSkipFee() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FoTApp", "FOT", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);
        AppStakingVault vault = AppStakingVault(app.vault);

        // Vault is exempt - no fee when staking
        // (This happens via the vault's deposit, but we can test exemption directly)

        // Bonding curve is exempt
        assertTrue(token.transferFeeExempt(app.curve));

        // Vault is exempt
        assertTrue(token.transferFeeExempt(address(vault)));
    }

    function test_FoT_GovernanceCanUpdateFee() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FoTApp", "FOT", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        // Governance can update fee (max 2%)
        uint16 newFeeBps = 200; // 2%

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit TransferFeeUpdated(100, newFeeBps);
        token.setTransferFeeBps(newFeeBps);

        assertEq(token.transferFeeBps(), newFeeBps);
    }

    function test_FoT_CannotExceedMaxFee() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FoTApp", "FOT", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        // Cannot set fee above 2%
        vm.prank(governance);
        vm.expectRevert(AppToken.FeeTooHigh.selector);
        token.setTransferFeeBps(201);
    }

    function test_FoT_GovernanceCanSetExemptions() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FoTApp", "FOT", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        address newExempt = makeAddr("newExempt");

        // Governance can add exemption
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit TransferFeeExemptSet(newExempt, true);
        token.setTransferFeeExempt(newExempt, true);

        assertTrue(token.transferFeeExempt(newExempt));
    }

    // ===== View Function Tests =====

    function test_Views_GetTransferFeeInfo() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("ViewApp", "VIEW", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        (uint16 feeBps, uint16 maxFeeBps, bool isExempt) = token.getTransferFeeInfo();

        assertEq(feeBps, 100); // 1% default
        assertEq(maxFeeBps, 200); // 2% max
        assertFalse(isExempt); // msg.sender not exempt
    }

    function test_Views_CalculateTransferFee() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("ViewApp", "VIEW", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        uint256 amount = 10000 ether;
        (uint256 fee, uint256 netAmount) = token.calculateTransferFee(amount);

        assertEq(fee, 100 ether); // 1%
        assertEq(netAmount, 9900 ether); // 99%
    }

    function test_Views_GetAppLaunchStatus() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("StatusApp", "STAT", 0, "", "", "");
        vm.stopPrank();

        (bool isInEarlyAccess, uint256 earlyAccessEndsAt, uint256 xpRequired) =
            factory.getAppLaunchStatus(appId);

        assertTrue(isInEarlyAccess);
        assertEq(xpRequired, 100 ether);
        assertGt(earlyAccessEndsAt, block.timestamp);
    }

    function test_Views_CanUserBuy() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("BuyApp", "BUY", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        assertTrue(curve.canUserBuy(xpUser));
        assertFalse(curve.canUserBuy(noXpUser));

        // After early access ends
        vm.warp(block.timestamp + 6 hours + 1);
        assertTrue(curve.canUserBuy(noXpUser));
    }

    function test_Views_GetEarlyAccessInfo() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("InfoApp", "INFO", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        (uint256 launchTime, uint256 duration, uint256 xpMin, bool isActive) =
            curve.getEarlyAccessInfo();

        assertEq(launchTime, block.timestamp);
        assertEq(duration, 6 hours);
        assertEq(xpMin, 100 ether);
        assertTrue(isActive);

        // After early access ends
        vm.warp(block.timestamp + 6 hours + 1);
        (,,, isActive) = curve.getEarlyAccessInfo();
        assertFalse(isActive);
    }
}
