// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock ELTA token
contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock app token
contract MockAppToken is ERC20 {
    constructor() ERC20("Mock App Token", "MAPP") {
        _mint(msg.sender, 10_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock Uniswap V2 Router
contract MockUniswapV2Router {
    MockELTA public elta;
    uint256 public exchangeRate = 10; // 1 app token = 10 ELTA

    constructor(address _elta) {
        elta = MockELTA(_elta);
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = amountIn * exchangeRate;
        require(amountOut >= amountOutMin, "Insufficient output");
        elta.transfer(to, amountOut);
    }
}

/// @notice Malicious router that tries to steal funds
contract MaliciousRouter {
    address public attacker;

    constructor(address _attacker) {
        attacker = _attacker;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address,
        uint256
    ) external {
        // Steal the tokens instead of swapping
        IERC20(path[0]).transferFrom(msg.sender, attacker, amountIn);
        // Don't send any ELTA back - this simulates theft
    }
}

/// @notice Router that returns less than minOut
contract BadRateRouter {
    MockELTA public elta;

    constructor(address _elta) {
        elta = MockELTA(_elta);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // Return only 1 wei of ELTA regardless of input
        elta.transfer(to, 1);
    }
}

/**
 * @title FeeSwapperSecurity
 * @notice Security tests for FeeSwapper - MEV protection, router security, slippage controls
 * @dev Tests attack vectors for the DEX swap integration
 */
contract FeeSwapperSecurity is Test {
    FeeSwapper public swapper;
    MockELTA public elta;
    MockAppToken public appToken;
    MockUniswapV2Router public router;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public feeManager = makeAddr("feeManager");
    address public attacker = makeAddr("attacker");
    address public caller = makeAddr("caller");

    uint256 public constant APP_ID = 1;

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

        // Give caller app tokens
        appToken.transfer(caller, 100_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MEV / SANDWICH ATTACK PROTECTION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SandwichAttackMitigatedBySlippage() public {
        uint256 amountIn = 1000 ether;
        uint256 expectedOut = amountIn * router.exchangeRate();
        uint256 minOut = (expectedOut * 95) / 100; // 5% slippage tolerance

        // Simulate sandwich attack - attacker front-runs and changes rate
        router.setExchangeRate(5); // Rate drops from 10 to 5 (50% worse)

        // User's swap should fail due to slippage protection
        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(); // Router reverts due to amountOutMin check
        swapper.swap(APP_ID, address(appToken), amountIn, minOut, address(router), path);
        vm.stopPrank();
    }

    function test_Security_SwapperDoesNotHoldFundsLongTerm() public {
        uint256 amountIn = 1000 ether;
        uint256 minOut = (amountIn * router.exchangeRate() * 95) / 100;

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        swapper.swap(APP_ID, address(appToken), amountIn, minOut, address(router), path);
        vm.stopPrank();

        // Swapper should have 0 balance - all ELTA forwarded to feeManager
        assertEq(elta.balanceOf(address(swapper)), 0);
        assertEq(appToken.balanceOf(address(swapper)), 0);
    }

    function test_Security_CallerCannotManipulatePath() public {
        uint256 amountIn = 1000 ether;

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        // Path must end in ELTA - anything else should fail
        address[] memory badPath = new address[](2);
        badPath[0] = address(appToken);
        badPath[1] = address(appToken); // Doesn't end in ELTA

        vm.expectRevert(FeeSwapper.InvalidAmount.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, 0, address(router), badPath);

        // Single element path should fail
        address[] memory shortPath = new address[](1);
        shortPath[0] = address(appToken);

        vm.expectRevert(FeeSwapper.InvalidAmount.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, 0, address(router), shortPath);

        vm.stopPrank();
    }

    function test_Security_MinSwapThresholdPreventsDustAttacks() public {
        // Set threshold
        vm.prank(governance);
        swapper.setMinSwapThreshold(10 ether);

        // Deposit dust amount to swapper
        appToken.transfer(address(swapper), 1 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // swapFromBalance should fail - below threshold
        vm.expectRevert(FeeSwapper.BelowMinSwapThreshold.selector);
        swapper.swapFromBalance(APP_ID, address(appToken), 1 ether, 0, address(router), path);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROUTER SECURITY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAllowlistedRoutersAccepted() public {
        address badRouter = makeAddr("badRouter");
        uint256 amountIn = 1000 ether;

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, 0, badRouter, path);
        vm.stopPrank();
    }

    function test_Security_MaliciousRouterCannotStealFunds() public {
        // Deploy malicious router
        MaliciousRouter maliciousRouter = new MaliciousRouter(attacker);

        // If governance were to allowlist it (simulating compromised governance)
        vm.prank(governance);
        swapper.setRouterAllowed(address(maliciousRouter), true);

        uint256 amountIn = 1000 ether;
        uint256 minOut = 9000 ether; // Expect 10x return

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Swap should fail because malicious router doesn't return ELTA
        vm.expectRevert(FeeSwapper.SwapFailed.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, minOut, address(maliciousRouter), path);
        vm.stopPrank();

        // Caller's tokens were not taken (approval reset on failure)
        // Note: The transfer happens before the swap call fails, so tokens may be lost
        // This test documents the risk of allowlisting malicious routers
    }

    function test_Security_RouterRemovalTakesEffectImmediately() public {
        uint256 amountIn = 1000 ether;

        // First swap works
        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn * 2);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        swapper.swap(APP_ID, address(appToken), amountIn, 0, address(router), path);
        vm.stopPrank();

        // Remove router
        vm.prank(governance);
        swapper.setRouterAllowed(address(router), false);

        // Second swap fails immediately
        vm.prank(caller);
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, 0, address(router), path);
    }

    function test_Security_EmptyRouterListBlocksAllSwaps() public {
        // Remove all routers
        vm.prank(governance);
        swapper.setRouterAllowed(address(router), false);

        uint256 amountIn = 1000 ether;

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, 0, address(router), path);
        vm.stopPrank();

        // Verify router list is empty
        address[] memory routers = swapper.getAllowedRouters();
        assertEq(routers.length, 0);
    }

    function test_Security_RouterCannotBeZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(FeeSwapper.ZeroAddress.selector);
        swapper.setRouterAllowed(address(0), true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SLIPPAGE CONTROLS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_MaxSlippageBpsEnforced() public {
        // Cannot set slippage > 10%
        vm.prank(governance);
        vm.expectRevert(FeeSwapper.SlippageTooHigh.selector);
        swapper.setMaxSlippageBps(1001); // 10.01%

        // Can set exactly 10%
        vm.prank(governance);
        swapper.setMaxSlippageBps(1000);
        assertEq(swapper.maxSlippageBps(), 1000);

        // Can set lower
        vm.prank(governance);
        swapper.setMaxSlippageBps(100); // 1%
        assertEq(swapper.maxSlippageBps(), 100);
    }

    function test_Security_CallerMinOutRespected() public {
        uint256 amountIn = 1000 ether;
        uint256 actualOut = amountIn * router.exchangeRate(); // 10,000 ELTA
        uint256 minOut = actualOut + 1; // Impossible to achieve

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(); // Router or swapper reverts
        swapper.swap(APP_ID, address(appToken), amountIn, minOut, address(router), path);
        vm.stopPrank();
    }

    function test_Security_SlippageCalculationAccurate() public {
        // Test exact minOut works
        uint256 amountIn = 1000 ether;
        uint256 exactOut = amountIn * router.exchangeRate();

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        uint256 amountOut = swapper.swap(APP_ID, address(appToken), amountIn, exactOut, address(router), path);
        assertEq(amountOut, exactOut);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyGovernanceCanSetRouter() public {
        address newRouter = makeAddr("newRouter");

        vm.prank(admin);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setRouterAllowed(newRouter, true);

        vm.prank(attacker);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setRouterAllowed(newRouter, true);

        vm.prank(governance);
        swapper.setRouterAllowed(newRouter, true);
        assertTrue(swapper.isRouterAllowed(newRouter));
    }

    function test_Security_OnlyGovernanceCanSetSlippage() public {
        vm.prank(admin);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setMaxSlippageBps(300);

        vm.prank(attacker);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setMaxSlippageBps(300);

        vm.prank(governance);
        swapper.setMaxSlippageBps(300);
        assertEq(swapper.maxSlippageBps(), 300);
    }

    function test_Security_OnlyAdminCanSetFeeManager() public {
        address newFeeManager = makeAddr("newFeeManager");

        vm.prank(governance);
        vm.expectRevert(FeeSwapper.OnlyAdmin.selector);
        swapper.setFeeManager(newFeeManager);

        vm.prank(attacker);
        vm.expectRevert(FeeSwapper.OnlyAdmin.selector);
        swapper.setFeeManager(newFeeManager);

        vm.prank(admin);
        swapper.setFeeManager(newFeeManager);
        assertEq(swapper.feeManager(), newFeeManager);
    }

    function test_Security_AdminAndGovernanceRoleSeparation() public {
        // Admin can transfer admin role
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        swapper.transferAdmin(newAdmin);
        assertEq(swapper.admin(), newAdmin);

        // Governance can transfer governance role
        address newGov = makeAddr("newGov");
        vm.prank(governance);
        swapper.transferGovernance(newGov);
        assertEq(swapper.governance(), newGov);

        // Admin cannot affect governance
        vm.prank(newAdmin);
        vm.expectRevert(FeeSwapper.OnlyGovernance.selector);
        swapper.setRouterAllowed(makeAddr("r"), true);

        // Governance cannot affect admin functions
        vm.prank(newGov);
        vm.expectRevert(FeeSwapper.OnlyAdmin.selector);
        swapper.setFeeManager(makeAddr("fm"));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SWAP EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_SwapFailureReverts() public {
        // Deploy bad router that returns less than minOut
        BadRateRouter badRouter = new BadRateRouter(address(elta));
        elta.transfer(address(badRouter), 1000 ether);

        vm.prank(governance);
        swapper.setRouterAllowed(address(badRouter), true);

        uint256 amountIn = 1000 ether;
        uint256 minOut = 9000 ether;

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.SwapFailed.selector);
        swapper.swap(APP_ID, address(appToken), amountIn, minOut, address(badRouter), path);
        vm.stopPrank();
    }

    function test_Security_SwapFromBalanceRequiresActualBalance() public {
        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        // Swapper has no balance
        assertEq(appToken.balanceOf(address(swapper)), 0);

        // Cannot swap phantom balance
        vm.expectRevert(FeeSwapper.InvalidAmount.selector);
        swapper.swapFromBalance(APP_ID, address(appToken), 1000 ether, 0, address(router), path);
    }

    function test_Security_ZeroAmountSwapBlocked() public {
        vm.startPrank(caller);
        appToken.approve(address(swapper), 1000 ether);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        vm.expectRevert(FeeSwapper.InvalidAmount.selector);
        swapper.swap(APP_ID, address(appToken), 0, 0, address(router), path);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_SwapAmounts(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 50_000 ether);

        uint256 minOut = (amountIn * router.exchangeRate() * 95) / 100;

        vm.startPrank(caller);
        appToken.approve(address(swapper), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(appToken);
        path[1] = address(elta);

        uint256 amountOut = swapper.swap(APP_ID, address(appToken), amountIn, minOut, address(router), path);
        assertGe(amountOut, minOut);
        vm.stopPrank();
    }

    function testFuzz_Security_SlippageValues(uint256 bps) public {
        bps = bound(bps, 1, 1000); // 0.01% to 10%

        vm.prank(governance);
        swapper.setMaxSlippageBps(bps);

        assertEq(swapper.maxSlippageBps(), bps);
    }

    function testFuzz_Security_RouterAllowlistOperations(uint8 numOps) public {
        numOps = uint8(bound(numOps, 1, 10));

        address[] memory routers = new address[](numOps);
        for (uint8 i = 0; i < numOps; i++) {
            routers[i] = makeAddr(string(abi.encodePacked("router", i)));

            // Add router
            vm.prank(governance);
            swapper.setRouterAllowed(routers[i], true);
            assertTrue(swapper.isRouterAllowed(routers[i]));
        }

        // Remove all
        for (uint8 i = 0; i < numOps; i++) {
            vm.prank(governance);
            swapper.setRouterAllowed(routers[i], false);
            assertFalse(swapper.isRouterAllowed(routers[i]));
        }
    }

    function testFuzz_Security_MinThreshold(uint256 threshold) public {
        threshold = bound(threshold, 0, 100 ether);

        vm.prank(governance);
        swapper.setMinSwapThreshold(threshold);

        assertEq(swapper.minSwapThreshold(), threshold);
    }
}
