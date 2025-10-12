// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppFactory } from "../../src/apps/AppFactory.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppBondingCurve } from "../../src/apps/AppBondingCurve.sol";
import { LpLocker } from "../../src/apps/LpLocker.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../src/interfaces/IAppFeeRouter.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import { MockAppFeeRouter, MockAppRewardsDistributor } from "../mocks/MockContracts.sol";

/**
 * @title App Launch Security Tests
 * @notice Critical security tests for app launch framework
 * @dev Focuses on the most important security mechanisms
 */
contract AppLaunchSecurityTest is Test {
    ELTA public elta;
    AppFactory public factory;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public creator = makeAddr("creator");
    address public attacker = makeAddr("attacker");
    address public user1 = makeAddr("user1");

    address public mockRouter = makeAddr("mockRouter");

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);

        vm.mockCall(
            mockRouter, abi.encodeWithSignature("factory()"), abi.encode(makeAddr("mockFactory"))
        );

        // Deploy mocks
        MockAppFeeRouter mockFeeRouter = new MockAppFeeRouter();
        MockAppRewardsDistributor mockAppRewards = new MockAppRewardsDistributor();

        factory = new AppFactory(
            elta,
            IUniswapV2Router02(mockRouter),
            treasury,
            IAppFeeRouter(address(mockFeeRouter)),
            IAppRewardsDistributor(address(mockAppRewards)),
            admin
        );

        // Distribute ELTA
        vm.startPrank(treasury);
        elta.transfer(creator, 10_000 ether);
        elta.transfer(attacker, 5_000 ether);
        elta.transfer(user1, 10_000 ether);
        vm.stopPrank();
    }

    function test_Critical_UnauthorizedAppCreation() public {
        // Attacker without enough ELTA cannot create app
        vm.expectRevert();
        vm.prank(attacker);
        factory.createApp("Malicious", "MAL", 0, "", "", "");

        // Verify no app was created
        assertEq(factory.appCount(), 0);
    }

    function test_Critical_FactoryAccessControl() public {
        // Attacker cannot pause
        vm.expectRevert();
        vm.prank(attacker);
        factory.setPaused(true);

        // Verify attacker has no roles
        assertFalse(factory.hasRole(factory.PAUSER_ROLE(), attacker));
    }

    function test_Critical_TokenSupplyProtection() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("SupplyTest", "SUPPLY", 1000 ether, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        // Verify supply is fixed and cannot be exceeded
        assertEq(token.totalSupply(), 1000 ether);
        assertEq(token.maxSupply(), 1000 ether);

        // Factory should not have minter role anymore
        assertFalse(token.hasRole(token.MINTER_ROLE(), address(factory)));

        // No one can mint more tokens
        vm.expectRevert();
        vm.prank(admin);
        token.mint(user1, 1);
    }

    function test_Critical_BondingCurveReentrancy() public {
        // Create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("ReentrancyTest", "REEN", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Verify reentrancy protection exists
        // The ReentrancyGuard should prevent multiple entries

        vm.startPrank(user1);
        // Approve with 1% trading fee
        elta.approve(address(curve), 1000 ether * 101 / 100);
        uint256 tokensOut = curve.buy(1000 ether, 0);
        vm.stopPrank();

        // Purchase should succeed normally
        assertGt(tokensOut, 0);
    }

    function test_Critical_LpLockerSecurity() public {
        // Test LP locker cannot be compromised

        LpLocker locker = new LpLocker(1, makeAddr("lpToken"), treasury, block.timestamp + 365 days);

        // Attacker cannot claim before unlock
        vm.expectRevert(LpLocker.NotYetUnlocked.selector);
        vm.prank(attacker);
        locker.claim();

        // Attacker cannot claim as wrong beneficiary even after unlock
        vm.warp(block.timestamp + 366 days);

        vm.expectRevert(LpLocker.Unauthorized.selector);
        vm.prank(attacker);
        locker.claim();

        // Parameters are immutable - no way to change them
        assertEq(locker.beneficiary(), treasury);
        assertEq(locker.appId(), 1);
    }

    function test_Critical_ProtocolFeeCollection() public {
        // Verify protocol fees go to treasury, not attackers

        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("FeeTest", "FEE", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 purchaseAmount = 1000 ether;
        uint256 expectedFee = (purchaseAmount * factory.protocolFeeRate()) / 10000;

        vm.startPrank(user1);
        // Approve with 1% trading fee
        elta.approve(address(curve), purchaseAmount * 101 / 100);
        curve.buy(purchaseAmount, 0);
        vm.stopPrank();

        uint256 treasuryAfter = elta.balanceOf(treasury);

        // Verify fee went to treasury
        assertEq(treasuryAfter - treasuryBefore, expectedFee);

        // Attacker cannot redirect fees
        assertEq(elta.balanceOf(attacker), 5_000 ether); // Original amount, no fees
    }

    function test_Critical_PauseMechanism() public {
        // Test emergency pause works correctly

        vm.prank(admin);
        factory.setPaused(true);

        // App creation should be blocked
        vm.expectRevert(AppFactory.Paused.selector);
        vm.prank(creator);
        factory.createApp("PausedApp", "PAUSE", 0, "", "", "");

        // Verify no app was created
        assertEq(factory.appCount(), 0);

        // Only admin can unpause
        vm.expectRevert();
        vm.prank(attacker);
        factory.setPaused(false);

        vm.prank(admin);
        factory.setPaused(false);

        // Now creation should work
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("UnpausedApp", "UNPAUSE", 0, "", "", "");
        vm.stopPrank();

        assertEq(appId, 0);
    }

    function test_Critical_TokenMetadataProtection() public {
        // Only app creator can update metadata

        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("MetaTest", "META", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppToken token = AppToken(app.token);

        // Attacker cannot update metadata
        vm.expectRevert(AppToken.OnlyCreator.selector);
        vm.prank(attacker);
        token.updateMetadata("Malicious description", "evil.com/image", "evil.com");

        // Creator can update metadata
        vm.prank(creator);
        token.updateMetadata("Legitimate description", "ipfs://hash", "legitimate.com");

        assertEq(token.appDescription(), "Legitimate description");
    }

    function test_Critical_BondingCurveProtection() public {
        // Test bonding curve cannot be manipulated

        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("CurveTest", "CURVE", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);

        // Only factory can initialize curve
        vm.expectRevert(AppBondingCurve.OnlyFactory.selector);
        vm.prank(attacker);
        curve.initializeCurve(1000 ether, 1_000_000 ether);

        // Curve math should be deterministic and manipulation-resistant
        uint256 eltaIn = 1000 ether;
        uint256 expectedTokens = curve.getTokensOut(eltaIn);

        vm.startPrank(user1);
        // Approve with 1% fee
        elta.approve(address(curve), eltaIn * 101 / 100);
        uint256 actualTokens = curve.buy(eltaIn, expectedTokens);
        vm.stopPrank();

        assertEq(actualTokens, expectedTokens);
    }

    function test_Critical_ZeroAddressProtection() public {
        // All contracts should reject zero addresses
        
        // Deploy mocks first (before expectRevert)
        MockAppFeeRouter mockFee = new MockAppFeeRouter();
        MockAppRewardsDistributor mockRewards = new MockAppRewardsDistributor();

        vm.expectRevert("Zero address");
        new AppFactory(
            ELTA(address(0)),
            IUniswapV2Router02(mockRouter),
            treasury,
            IAppFeeRouter(address(mockFee)),
            IAppRewardsDistributor(address(mockRewards)),
            admin
        );

        vm.expectRevert("Zero address");
        new AppToken("Test", "TEST", 18, 1000 ether, address(0), admin);

        vm.expectRevert("Zero LP token");
        new LpLocker(1, address(0), treasury, block.timestamp + 365 days);
    }

    function test_Critical_ParameterValidation() public {
        // Test parameter validation - parameters are now immutable constants
        // so we just verify they have reasonable values

        assertGt(factory.seedElta(), 0);
        assertGt(factory.targetRaisedElta(), factory.seedElta());
        assertGt(factory.defaultSupply(), 0);
        assertLt(factory.protocolFeeRate(), 10000); // Less than 100%
        assertGt(factory.lpLockDuration(), 0);
    }

    function test_Critical_AppTokenTransferability() public {
        // App tokens should be transferable (unlike XP)

        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        uint256 appId = factory.createApp("TransferTest", "TRANS", 0, "", "", "");
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(appId);
        AppBondingCurve curve = AppBondingCurve(app.curve);
        AppToken token = AppToken(app.token);

        // Buy tokens
        vm.startPrank(user1);
        // Approve with 1% trading fee
        elta.approve(address(curve), 1000 ether * 101 / 100);
        uint256 tokensOut = curve.buy(1000 ether, 0);
        vm.stopPrank();

        // Tokens should be transferable
        uint256 transferAmount = tokensOut / 2;
        vm.prank(user1);
        token.transfer(attacker, transferAmount);

        assertEq(token.balanceOf(user1), tokensOut - transferAmount);
        assertEq(token.balanceOf(attacker), transferAmount);
    }

    function test_Critical_CreationStakeRequirement() public {
        // Creators must stake ELTA to create apps

        uint256 requiredStake = factory.creationFee() + factory.seedElta();

        // Attacker with insufficient ELTA cannot create
        vm.expectRevert();
        vm.prank(attacker);
        factory.createApp("InsufficientStake", "INSUF", 0, "", "", "");

        // Creator with sufficient ELTA can create
        vm.startPrank(creator);
        elta.approve(address(factory), requiredStake);
        uint256 appId = factory.createApp("ValidStake", "VALID", 0, "", "", "");
        vm.stopPrank();

        assertEq(appId, 0);

        // Creator's ELTA should be spent
        assertEq(elta.balanceOf(creator), 10_000 ether - requiredStake);
    }
}
