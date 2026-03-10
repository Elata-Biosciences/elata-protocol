// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ELTA} from "elta/ELTA.sol";
import {FeeKind} from "../../../src/fees/FeeKind.sol";
import {FeeSwapper} from "../../../src/fees/FeeSwapper.sol";
import {FeeCollector} from "../../../src/fees/FeeCollector.sol";
import {AppRegistry} from "../../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../../src/contributors/ContributorSplitFactory.sol";
import {IContributorSplit} from "../../../src/interfaces/IContributorSplit.sol";

/// @notice Simple mintable ERC20 used as token-in for swaps.
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @dev Minimal Uniswap-like router stub that supports the exact function signature
 * FeeSwapper calls, and transfers a deterministic amount of ELTA to `to`.
 */
contract MockSwapRouter {
    MockToken public immutable tokenIn;
    ELTA public immutable elta;
    uint256 public rateBps = 10_000; // 1:1 by default

    constructor(address _tokenIn, address _elta) {
        tokenIn = MockToken(_tokenIn);
        elta = ELTA(_elta);
    }

    function setRateBps(uint256 newRateBps) external {
        rateBps = newRateBps;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256, /* minOut - FeeSwapper enforces via balance diff */
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external {
        require(path.length >= 2, "bad path");
        require(path[0] == address(tokenIn), "bad in");
        require(path[path.length - 1] == address(elta), "bad out");

        // Pull tokenIn from caller (FeeSwapper) using allowance.
        tokenIn.transferFrom(msg.sender, address(this), amountIn);

        // Send ELTA to the FeeSwapper (as `to`) so FeeSwapper observes balance increase.
        uint256 out = (amountIn * rateBps) / 10_000;
        elta.transfer(to, out);
    }
}

/**
 * @title TreasurySettlementSecurity
 * @notice Security tests for the vNext fee routing model (no epoch settlement):
 *         FeeCollector -> FeeSwapper -> Treasury (+ ContributorSplit for app revenue)
 */
contract TreasurySettlementSecurity is Test {
    uint256 internal constant APP_ID = 1;

    ELTA internal elta;
    AppRegistry internal registry;
    ContributorSplitFactory internal splitFactory;
    FeeSwapper internal feeSwapper;
    FeeCollector internal feeCollector;
    address internal split;

    MockToken internal tokenIn;
    MockSwapRouter internal router;

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal ownerSafe = makeAddr("ownerSafe");
    address internal contributor = makeAddr("contributor");
    address internal payer = makeAddr("payer");

    function setUp() public {
        elta = new ELTA(treasury);

        // App-factory gated registries: make the test contract the appFactory.
        registry = new AppRegistry(admin, address(this));
        splitFactory = new ContributorSplitFactory(admin, address(this));

        feeSwapper = new FeeSwapper(address(elta), admin, admin, treasury, address(registry));
        feeCollector = new FeeCollector(address(elta), admin, address(feeSwapper), address(feeSwapper));

        // Register app + contributor split.
        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: contributor, shares: 10_000});
        split = splitFactory.createSplit(APP_ID, ownerSafe, address(feeSwapper), contributors);
        registry.registerApp(APP_ID, ownerSafe, split, "");

        // Fund payer.
        vm.startPrank(treasury);
        elta.transfer(payer, 1_000_000 ether);
        vm.stopPrank();

        vm.prank(payer);
        elta.approve(address(feeCollector), type(uint256).max);

        // Swap helper fixture.
        tokenIn = new MockToken("TokenIn", "TIN");
        router = new MockSwapRouter(address(tokenIn), address(elta));

        // Fund router with ELTA output liquidity.
        vm.startPrank(treasury);
        elta.transfer(address(router), 1_000_000 ether);
        vm.stopPrank();

        // Allowlist router.
        vm.prank(admin);
        feeSwapper.setRouterAllowed(address(router), true);
    }

    function test_Security_AllFeesSplit80_20_ByDefault() public {
        uint256 amount = 10_000 ether;
        uint16 takeBps = feeSwapper.defaultTreasuryTakeBps();

        uint256 expectedTreasury = (amount * uint256(takeBps)) / 10_000;
        uint256 expectedContributors = amount - expectedTreasury;

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(split);

        vm.prank(payer);
        feeCollector.depositElta(APP_ID, FeeKind.TRADING_FEE, amount);

        feeCollector.sweepElta(APP_ID, FeeKind.TRADING_FEE);

        assertEq(elta.balanceOf(treasury) - treasuryBefore, expectedTreasury);
        assertEq(elta.balanceOf(split) - splitBefore, expectedContributors);
    }

    function test_Security_AppRevenueSplitsTreasuryTakeAndContributors() public {
        uint256 amount = 10_000 ether;
        uint16 takeBps = feeSwapper.defaultTreasuryTakeBps();

        uint256 expectedTreasury = (amount * uint256(takeBps)) / 10_000;
        uint256 expectedContributors = amount - expectedTreasury;

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(split);

        vm.prank(payer);
        feeCollector.depositElta(APP_ID, FeeKind.OTHER, amount);

        feeCollector.sweepElta(APP_ID, FeeKind.OTHER);

        assertEq(elta.balanceOf(treasury) - treasuryBefore, expectedTreasury);
        assertEq(elta.balanceOf(split) - splitBefore, expectedContributors);
    }

    function test_Security_PausedAppForcesAllRoutingToTreasury() public {
        uint256 amount = 10_000 ether;

        // Pause app via governance.
        vm.prank(admin);
        registry.setPaused(APP_ID, true);

        uint256 treasuryBefore = elta.balanceOf(treasury);

        vm.prank(payer);
        feeCollector.depositElta(APP_ID, FeeKind.CONTENT_SALE, amount);

        feeCollector.sweepElta(APP_ID, FeeKind.CONTENT_SALE);

        // When paused, app revenue is treated as protocol-controlled -> treasury.
        assertEq(elta.balanceOf(treasury) - treasuryBefore, amount);
    }

    function test_Security_SwapFromBalance_RevertsWhenRouterNotAllowed() public {
        vm.prank(admin);
        feeSwapper.setRouterAllowed(address(router), false);

        tokenIn.mint(address(feeSwapper), 10 ether);
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        feeSwapper.swapFromBalance(APP_ID, FeeKind.TRADING_FEE, address(tokenIn), 10 ether, 1, address(router), path);
    }

    function test_Security_SwapFromBalance_RevertsBelowMinThreshold() public {
        vm.prank(admin);
        feeSwapper.setMinSwapThreshold(100 ether);

        tokenIn.mint(address(feeSwapper), 10 ether);
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        feeSwapper.swapFromBalance(APP_ID, FeeKind.TRADING_FEE, address(tokenIn), 10 ether, 1, address(router), path);
    }

    function test_Security_SwapFromBalance_RevertsOnInsufficientOut() public {
        tokenIn.mint(address(feeSwapper), 1_000 ether);

        // Make router send 0 ELTA out.
        router.setRateBps(0);

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.SwapFailed.selector);
        feeSwapper.swapFromBalance(APP_ID, FeeKind.TRADING_FEE, address(tokenIn), 1_000 ether, 1, address(router), path);
    }

    function test_Security_SwapFromBalance_SwapsAndRoutes() public {
        uint256 amountIn = 1_000 ether;
        tokenIn.mint(address(feeSwapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(elta);

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(split);
        uint256 amountOut = feeSwapper.swapFromBalance(
            APP_ID, FeeKind.TRADING_FEE, address(tokenIn), amountIn, 1, address(router), path
        );

        uint256 expectedTreasury = (amountOut * feeSwapper.defaultTreasuryTakeBps()) / 10_000;
        uint256 expectedSplit = amountOut - expectedTreasury;
        assertEq(elta.balanceOf(treasury) - treasuryBefore, expectedTreasury);
        assertEq(elta.balanceOf(split) - splitBefore, expectedSplit);
    }
}

