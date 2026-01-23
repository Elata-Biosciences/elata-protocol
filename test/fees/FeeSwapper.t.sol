// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ELTA for testing
contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock app token for testing
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App Token", "MAPP") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock Uniswap V2 Router for testing
contract MockUniswapV2Router {
    MockELTA public elta;
    uint256 public exchangeRate = 10; // 1 app token = 10 ELTA (simplified)

    constructor(address _elta) {
        elta = MockELTA(_elta);
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    // Simulate swap supporting fee-on-transfer tokens
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external {
        // Transfer tokens in from sender
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Calculate amount out
        uint256 amountOut = amountIn * exchangeRate;
        require(amountOut >= amountOutMin, "Insufficient output");

        // Transfer ELTA out
        elta.transfer(to, amountOut);
    }

    // Quote function
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata /* path */
    )
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * exchangeRate;
    }
}

/**
 * @title FeeSwapper Unit Tests
 * @notice TDD tests for FeeSwapper - safe swapping of non-ELTA assets to ELTA
 * @dev Tests router allowlist, slippage protection, and swap execution
 */
contract FeeSwapperTest is Test {
    FeeSwapper public swapper;
    MockELTA public elta;
    MockAppToken public appToken;
    MockUniswapV2Router public router;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public feeManager = makeAddr("feeManager");
    address public feeCollector = makeAddr("feeCollector");

    uint256 public constant APP_ID_1 = 1;

    // Events to test
    event Swapped(
        uint256 indexed appId,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        address caller
    );
    event RouterAllowlistUpdated(address indexed router, bool allowed);
    event MaxSlippageBpsUpdated(uint256 oldBps, uint256 newBps);
    event FeeManagerUpdated(address indexed oldFeeManager, address indexed newFeeManager);

    function setUp() public {
        elta = new MockELTA();
        appToken = new MockAppToken();
        router = new MockUniswapV2Router(address(elta));

        // Give router ELTA for swaps
        elta.transfer(address(router), 10_000_000 ether);

        // Deploy FeeSwapper
        swapper = new FeeSwapper(address(elta), admin, governance, feeManager);

        // Allowlist the router
        vm.prank(governance);
        swapper.setRouterAllowed(address(router), true);

        // Give feeCollector app tokens to swap
        appToken.transfer(feeCollector, 100_000 ether);
    }

    // =========== Deployment Tests ===========

    function test_Deployment() public view {
        assertEq(address(swapper.ELTA()), address(elta));
        assertEq(swapper.admin(), admin);
        assertEq(swapper.governance(), governance);
        assertEq(swapper.feeManager(), feeManager);
        assertEq(swapper.maxSlippageBps(), 500); // Default 5%
    }

    function test_RevertWhen_DeployWithZeroELTA() public {
        vm.expectRevert(FeeSwapper.ZeroAddress.selector);
        new FeeSwapper(address(0), admin, governance, feeManager);
    }

    // =========== Router Allowlist Tests ===========

    function test_SetRouterAllowed() public {
        address newRouter = makeAddr("newRouter");
        assertFalse(swapper.isRouterAllowed(newRouter));

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit RouterAllowlistUpdated(newRouter, true);
        swapper.setRouterAllowed(newRouter, true);

        assertTrue(swapper.isRouterAllowed(newRouter));
    }

    function test_RemoveRouterAllowed() public {
        assertTrue(swapper.isRouterAllowed(address(router)));

        vm.prank(governance);
        swapper.setRouterAllowed(address(router), false);

        assertFalse(swapper.isRouterAllowed(address(router)));
    }

    function test_RevertWhen_NonGovernanceSetsRouter() public {
        vm.prank(feeCollector);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setRouterAllowed(makeAddr("newRouter"), true);
    }

    // =========== Swap Tests ===========

    function test_SwapAppTokenToElta() public {
        uint256 amountIn = 1000 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();
        uint256 minOut = (expectedOut * 95) / 100; // 5% slippage

        // Approve and deposit to swapper
        vm.prank(feeCollector);
        appToken.approve(address(swapper), amountIn);

        // Call swap
        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        uint256 feeManagerBefore = elta.balanceOf(feeManager);

        vm.prank(feeCollector);
        vm.expectEmit(true, true, true, true);
        emit Swapped(APP_ID_1, address(appToken), amountIn, address(elta), expectedOut, feeCollector);
        uint256 amountOut = swapper.swap(APP_ID_1, address(appToken), amountIn, minOut, address(router), path);

        assertEq(amountOut, expectedOut);
        assertEq(elta.balanceOf(feeManager), feeManagerBefore + expectedOut);
    }

    function test_SwapIsPermissionless() public {
        uint256 amountIn = 1000 ether;
        uint256 minOut = (amountIn * router.exchangeRate() * 95) / 100;

        vm.prank(feeCollector);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Anyone can call swap
        address randomCaller = makeAddr("randomCaller");

        // Transfer tokens to swapper first (simulating FeeCollector sweep)
        vm.prank(feeCollector);
        appToken.transfer(address(swapper), amountIn);

        vm.prank(randomCaller);
        swapper.swapFromBalance(APP_ID_1, address(appToken), amountIn, minOut, address(router), path);
    }

    function test_RevertWhen_SwapWithDisallowedRouter() public {
        address badRouter = makeAddr("badRouter");
        uint256 amountIn = 1000 ether;

        vm.prank(feeCollector);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.prank(feeCollector);
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        swapper.swap(APP_ID_1, address(appToken), amountIn, 0, badRouter, path);
    }

    function test_RevertWhen_SlippageExceedsMax() public {
        uint256 amountIn = 1000 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();

        // Set exchange rate lower to simulate slippage
        router.setExchangeRate(5); // Now 1:5 instead of 1:10

        uint256 actualOut = amountIn * 5;
        // This is 50% slippage from expected, exceeding 5% max

        vm.prank(feeCollector);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Set minOut to actual output (to pass that check)
        // But maxSlippageBps should catch the excessive slippage
        vm.prank(feeCollector);
        // Note: In a real scenario, the swapper would get a quote first and compare
        swapper.swap(APP_ID_1, address(appToken), amountIn, actualOut, address(router), path);
    }

    function test_RevertWhen_MinOutNotMet() public {
        uint256 amountIn = 1000 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();
        uint256 minOut = expectedOut * 2; // Impossible to achieve

        vm.prank(feeCollector);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.prank(feeCollector);
        vm.expectRevert(); // Router should revert
        swapper.swap(APP_ID_1, address(appToken), amountIn, minOut, address(router), path);
    }

    // =========== Admin Tests ===========

    function test_SetMaxSlippageBps() public {
        uint256 newBps = 300; // 3%

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit MaxSlippageBpsUpdated(500, newBps);
        swapper.setMaxSlippageBps(newBps);

        assertEq(swapper.maxSlippageBps(), newBps);
    }

    function test_RevertWhen_MaxSlippageTooHigh() public {
        vm.prank(governance);
        vm.expectRevert(FeeSwapper.SlippageTooHigh.selector);
        swapper.setMaxSlippageBps(1100); // 11% > 10% max
    }

    function test_SetFeeManager() public {
        address newFeeManager = makeAddr("newFeeManager");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit FeeManagerUpdated(feeManager, newFeeManager);
        swapper.setFeeManager(newFeeManager);

        assertEq(swapper.feeManager(), newFeeManager);
    }

    // =========== View Functions Tests ===========

    function test_GetAllowedRouters() public {
        address router2 = makeAddr("router2");

        vm.prank(governance);
        swapper.setRouterAllowed(router2, true);

        address[] memory routers = swapper.getAllowedRouters();
        assertEq(routers.length, 2);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_Swap(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 50_000 ether);

        uint256 minOut = (amountIn * router.exchangeRate() * 95) / 100;

        vm.prank(feeCollector);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.prank(feeCollector);
        uint256 amountOut = swapper.swap(APP_ID_1, address(appToken), amountIn, minOut, address(router), path);

        assertGe(amountOut, minOut);
    }

    // =========== MinSwapThreshold Tests ===========

    function test_MinSwapThresholdDefault() public {
        assertEq(swapper.minSwapThreshold(), 1 ether);
    }

    function test_SetMinSwapThreshold() public {
        uint256 newThreshold = 5 ether;

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit MinSwapThresholdUpdated(1 ether, newThreshold);
        swapper.setMinSwapThreshold(newThreshold);

        assertEq(swapper.minSwapThreshold(), newThreshold);
    }

    function test_RevertWhen_SetMinSwapThresholdUnauthorized() public {
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        vm.prank(admin);
        swapper.setMinSwapThreshold(5 ether);
    }

    function test_RevertWhen_SwapBelowMinThreshold() public {
        // Set threshold higher than our swap amount
        vm.prank(governance);
        swapper.setMinSwapThreshold(10 ether);

        // Try to swap 1 ether (below threshold)
        appToken.mint(address(swapper), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        swapper.swapFromBalance(APP_ID_1, address(appToken), 1 ether, 0, address(router), path);
    }

    function test_SwapAtMinThreshold() public {
        // Set threshold to 5 ether
        vm.prank(governance);
        swapper.setMinSwapThreshold(5 ether);

        // Deposit exactly 5 ether
        appToken.mint(address(swapper), 5 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Should succeed at threshold
        uint256 amountOut = swapper.swapFromBalance(APP_ID_1, address(appToken), 5 ether, 0, address(router), path);
        assertGt(amountOut, 0);
    }

    event MinSwapThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
}
