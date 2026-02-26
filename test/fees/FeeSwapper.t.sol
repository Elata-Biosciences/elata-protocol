// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplit} from "../../src/contributors/ContributorSplit.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }
}

contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App Token", "MAPP") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract MockUniswapV2Router {
    MockELTA public elta;
    uint256 public exchangeRate = 10;

    constructor(address _elta) {
        elta = MockELTA(_elta);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = amountIn * exchangeRate;
        require(amountOut >= amountOutMin, "Insufficient output");
        elta.transfer(to, amountOut);
    }
}

contract FeeSwapperTest is Test {
    FeeSwapper swapper;
    MockELTA elta;
    MockAppToken appToken;
    MockUniswapV2Router router;
    AppRegistry registry;
    ContributorSplit split;

    address admin = makeAddr("admin");
    address governance = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address user = makeAddr("user");

    event Swapped(
        uint256 indexed appId,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address caller
    );
    event RouterAllowlistUpdated(address indexed router, bool allowed);

    function setUp() public {
        elta = new MockELTA();
        appToken = new MockAppToken();
        router = new MockUniswapV2Router(address(elta));
        registry = new AppRegistry(governance, address(this));

        // Seed router with ELTA for swaps
        elta.transfer(address(router), 10_000_000 ether);

        swapper = new FeeSwapper(address(elta), admin, governance, treasury, address(registry));

        vm.prank(governance);
        swapper.setRouterAllowed(address(router), true);

        // Register a test app with a real ContributorSplit, so app-revenue routing can be tested.
        split = new ContributorSplit();
        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: user, shares: 10_000});
        split.initialize(0, user, address(swapper), 200, contributors);

        vm.prank(address(this));
        registry.registerApp(0, user, address(split), "ipfs://meta");

        // Fund user with input tokens
        appToken.transfer(user, 10_000 ether);
    }

    function test_SwapRoutesProtocolFeesToTreasury() public {
        uint256 amountIn = 100 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.startPrank(user);
        appToken.approve(address(swapper), amountIn);

        vm.expectEmit(true, true, true, true);
        emit Swapped(0, address(appToken), amountIn, address(elta), expectedOut, user);

        // Protocol-owned FeeKind routes 100% to treasury.
        swapper.swap(0, FeeKind.LAUNCH_FEE, address(appToken), amountIn, 0, address(router), path);
        vm.stopPrank();

        assertEq(elta.balanceOf(treasury), expectedOut);
        assertEq(elta.balanceOf(address(swapper)), 0);
    }

    function test_SetRouterAllowedEmitsEvent() public {
        address newRouter = makeAddr("newRouter");
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit RouterAllowlistUpdated(newRouter, true);
        swapper.setRouterAllowed(newRouter, true);
        assertTrue(swapper.isRouterAllowed(newRouter));
    }

    function test_SwapFromBalance_RevertsBelowThreshold() public {
        vm.prank(governance);
        swapper.setMinSwapThreshold(1000 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Seed swapper with input token balance, but below threshold.
        appToken.transfer(address(swapper), 10 ether);

        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        swapper.swapFromBalance(0, FeeKind.CONTENT_SALE, address(appToken), 10 ether, 0, address(router), path);
    }

    function test_SwapFromBalance_RoutesAppRevenueToTreasuryAndSplit() public {
        uint256 amountIn = 100 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Seed swapper with input token balance.
        appToken.transfer(address(swapper), amountIn);

        uint256 treasuryBefore = elta.balanceOf(treasury);
        uint256 splitBefore = elta.balanceOf(address(split));

        swapper.swapFromBalance(0, FeeKind.CONTENT_SALE, address(appToken), amountIn, 0, address(router), path);

        // Default treasury take is 20% of app revenue.
        uint256 expectedTreasury = expectedOut * 2000 / 10_000;
        uint256 expectedSplit = expectedOut - expectedTreasury;

        assertEq(elta.balanceOf(treasury) - treasuryBefore, expectedTreasury);
        assertEq(elta.balanceOf(address(split)) - splitBefore, expectedSplit);
    }
}

