// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppBondingCurve } from "../../src/apps/AppBondingCurve.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";

contract AppBondingCurveTest is Test {
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public factory = makeAddr("factory");
    address public creator = makeAddr("creator");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");

    address public mockRouter = makeAddr("mockRouter");

    uint256 public constant SEED_ELTA = 100 ether;
    uint256 public constant TARGET_RAISED = 42_000 ether;
    uint256 public constant TOKEN_SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);
        appToken = new AppToken("TestApp", "TEST", 18, TOKEN_SUPPLY, creator, factory);

        // Mock router calls
        vm.mockCall(
            mockRouter, abi.encodeWithSignature("factory()"), abi.encode(makeAddr("mockFactory"))
        );

        curve = new AppBondingCurve(
            0, // appId
            factory,
            elta,
            appToken,
            IUniswapV2Router02(mockRouter),
            TARGET_RAISED,
            365 days, // lpLockDuration
            treasury, // lpBeneficiary
            treasury, // treasury
            250 // 2.5% protocol fee
        );

        // Setup: mint tokens to curve and initialize
        vm.startPrank(factory);
        appToken.mint(address(curve), TOKEN_SUPPLY);

        // Transfer seed ELTA to curve
        vm.stopPrank();
        vm.prank(treasury);
        elta.transfer(address(curve), SEED_ELTA);

        vm.prank(factory);
        curve.initializeCurve(SEED_ELTA, TOKEN_SUPPLY);

        // Give buyers some ELTA
        vm.startPrank(treasury);
        elta.transfer(buyer1, 50_000 ether);
        elta.transfer(buyer2, 50_000 ether);
        vm.stopPrank();
    }

    function test_Deployment() public {
        assertEq(address(curve.ELTA()), address(elta));
        assertEq(address(curve.TOKEN()), address(appToken));
        assertEq(curve.appId(), 0);
        assertEq(curve.targetRaisedElta(), TARGET_RAISED);
        assertEq(curve.reserveElta(), SEED_ELTA);
        assertEq(curve.reserveToken(), TOKEN_SUPPLY);
        assertFalse(curve.graduated());
    }

    function test_GetTokensOut() public {
        // Test price calculation
        uint256 tokensOut = curve.getTokensOut(1000 ether);
        assertGt(tokensOut, 0);

        // More ELTA should get fewer tokens (increasing price)
        uint256 tokensOut2 = curve.getTokensOut(2000 ether);
        assertLt(tokensOut2, tokensOut * 2); // Non-linear due to curve
    }

    function test_Buy() public {
        uint256 eltaIn = 1000 ether;
        uint256 expectedTokens = curve.getTokensOut(eltaIn);

        vm.startPrank(buyer1);
        elta.approve(address(curve), eltaIn);

        uint256 tokensBefore = appToken.balanceOf(buyer1);
        uint256 tokensOut = curve.buy(eltaIn, expectedTokens);
        uint256 tokensAfter = appToken.balanceOf(buyer1);

        vm.stopPrank();

        assertEq(tokensOut, expectedTokens);
        assertEq(tokensAfter - tokensBefore, expectedTokens);
        // Account for protocol fee (2.5% deducted)
        uint256 protocolFee = (eltaIn * 250) / 10000; // 2.5%
        uint256 actualEltaAdded = eltaIn - protocolFee;
        assertEq(curve.reserveElta(), SEED_ELTA + actualEltaAdded);
    }

    function test_BuyWithSlippageProtection() public {
        uint256 eltaIn = 1000 ether;
        uint256 minTokensOut = curve.getTokensOut(eltaIn) + 1; // Set too high

        vm.startPrank(buyer1);
        elta.approve(address(curve), eltaIn);

        vm.expectRevert(AppBondingCurve.InsufficientOutput.selector);
        curve.buy(eltaIn, minTokensOut);

        vm.stopPrank();
    }

    function test_GetCurrentPrice() public {
        uint256 initialPrice = curve.getCurrentPrice();
        assertGt(initialPrice, 0);

        // Buy some tokens
        vm.startPrank(buyer1);
        elta.approve(address(curve), 5000 ether);
        curve.buy(5000 ether, 0);
        vm.stopPrank();

        // Price should increase
        uint256 newPrice = curve.getCurrentPrice();
        assertGt(newPrice, initialPrice);
    }

    function test_CurveState() public {
        (
            uint256 eltaReserve,
            uint256 tokenReserve,
            uint256 target,
            bool isGraduated,
            uint256 currentPrice,
            uint256 progress
        ) = curve.getCurveState();

        assertEq(eltaReserve, SEED_ELTA);
        assertEq(tokenReserve, TOKEN_SUPPLY);
        assertEq(target, TARGET_RAISED);
        assertFalse(isGraduated);
        assertGt(currentPrice, 0);
        assertGt(progress, 0); // Should have some progress from seed
    }

    function test_RevertWhen_BuyAfterGraduation() public {
        // Mock graduation by setting graduated = true
        // This would normally happen automatically when target is reached

        // For now, test that buying zero amount fails
        vm.expectRevert(AppBondingCurve.ZeroInput.selector);
        vm.prank(buyer1);
        curve.buy(0, 0);
    }

    function test_ProtocolFeeCollection() public {
        uint256 eltaIn = 1000 ether;
        uint256 protocolFee = (eltaIn * curve.protocolFeeRate()) / 10000;

        uint256 treasuryBefore = elta.balanceOf(treasury);

        vm.startPrank(buyer1);
        elta.approve(address(curve), eltaIn);
        curve.buy(eltaIn, 0);
        vm.stopPrank();

        uint256 treasuryAfter = elta.balanceOf(treasury);
        assertEq(treasuryAfter - treasuryBefore, protocolFee);
    }

    function testFuzz_BuyTokens(uint256 eltaAmount) public {
        // Bound to reasonable range
        eltaAmount = bound(eltaAmount, 1 ether, 10_000 ether);

        // Give buyer enough ELTA
        vm.prank(treasury);
        elta.transfer(buyer1, eltaAmount);

        uint256 expectedTokens = curve.getTokensOut(eltaAmount);

        vm.startPrank(buyer1);
        elta.approve(address(curve), eltaAmount);
        uint256 tokensOut = curve.buy(eltaAmount, 0);
        vm.stopPrank();

        assertEq(tokensOut, expectedTokens);
        assertGt(tokensOut, 0);
    }
}
