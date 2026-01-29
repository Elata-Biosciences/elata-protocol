// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title UniswapForkTest
 * @notice Fork tests for Uniswap V2 integration on Base mainnet
 * @dev Tests graduation liquidity creation against real Uniswap contracts
 *
 * To run these tests:
 *   forge test --match-contract UniswapForkTest --fork-url $BASE_RPC_URL -vvv
 *
 * Environment:
 *   BASE_RPC_URL: RPC endpoint for Base mainnet (e.g., https://mainnet.base.org)
 *
 * Note: These tests require a Base mainnet RPC endpoint to run.
 * They will be skipped if no fork URL is provided.
 */
contract UniswapForkTest is Test {
    // Base mainnet addresses
    address constant UNISWAP_V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Uniswap V2 on Base
    address constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6; // Uniswap V2 Factory on Base
    address constant WETH = 0x4200000000000000000000000000000000000006; // WETH on Base

    // Test addresses
    address public admin;
    address public user;

    function setUp() public {
        // Skip if not forking
        if (block.chainid != 8453) {
            // Base mainnet chain ID
            return;
        }

        admin = makeAddr("admin");
        user = makeAddr("user");

        // Fund test accounts
        vm.deal(admin, 100 ether);
        vm.deal(user, 100 ether);
    }

    modifier onlyFork() {
        if (block.chainid != 8453) {
            console2.log("Skipping fork test - not on Base mainnet fork");
            return;
        }
        _;
    }

    // =========== Router Tests ===========

    /// @notice Verify Uniswap V2 Router is accessible on Base
    function test_Fork_RouterExists() public onlyFork {
        // Check router has code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(UNISWAP_V2_ROUTER)
        }
        assertGt(codeSize, 0, "Router has no code");

        // Check factory is set
        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        address factory = router.factory();
        assertEq(factory, UNISWAP_V2_FACTORY, "Factory mismatch");

        console2.log("Router factory:", factory);
        console2.log("Router WETH:", router.WETH());
    }

    /// @notice Test creating a new pair on Base
    function test_Fork_CreatePair() public onlyFork {
        // Deploy mock tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);

        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY);

        // Create pair
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertFalse(pair == address(0), "Pair creation failed");

        console2.log("Created pair:", pair);

        // Verify pair is retrievable
        address retrievedPair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(pair, retrievedPair, "Pair retrieval mismatch");
    }

    /// @notice Test adding liquidity to a new pair
    function test_Fork_AddLiquidity() public onlyFork {
        // Deploy mock tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);

        // Mint tokens
        uint256 amountA = 1000e18;
        uint256 amountB = 1000e18;
        tokenA.mint(admin, amountA);
        tokenB.mint(admin, amountB);

        // Approve router
        vm.startPrank(admin);
        tokenA.approve(UNISWAP_V2_ROUTER, amountA);
        tokenB.approve(UNISWAP_V2_ROUTER, amountB);

        // Add liquidity
        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        (uint256 actualA, uint256 actualB, uint256 liquidity) = router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0, // amountAMin
            0, // amountBMin
            admin,
            block.timestamp + 1 hours
        );
        vm.stopPrank();

        console2.log("Added liquidity A:", actualA);
        console2.log("Added liquidity B:", actualB);
        console2.log("LP tokens received:", liquidity);

        assertGt(liquidity, 0, "No LP tokens received");

        // Verify LP tokens
        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY);
        address pair = factory.getPair(address(tokenA), address(tokenB));
        uint256 lpBalance = IUniswapV2Pair(pair).balanceOf(admin);
        assertEq(lpBalance, liquidity, "LP balance mismatch");
    }

    /// @notice Test swapping tokens
    function test_Fork_SwapTokens() public onlyFork {
        // Deploy mock tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);

        // Mint and add liquidity
        uint256 liquidityA = 10000e18;
        uint256 liquidityB = 10000e18;
        tokenA.mint(admin, liquidityA);
        tokenB.mint(admin, liquidityB);

        vm.startPrank(admin);
        tokenA.approve(UNISWAP_V2_ROUTER, liquidityA);
        tokenB.approve(UNISWAP_V2_ROUTER, liquidityB);

        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        router.addLiquidity(
            address(tokenA), address(tokenB), liquidityA, liquidityB, 0, 0, admin, block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Mint tokens for swap
        uint256 swapAmount = 100e18;
        tokenA.mint(user, swapAmount);

        // Perform swap
        vm.startPrank(user);
        tokenA.approve(UNISWAP_V2_ROUTER, swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 balanceBefore = tokenB.balanceOf(user);
        router.swapExactTokensForTokens(swapAmount, 0, path, user, block.timestamp + 1 hours);
        uint256 balanceAfter = tokenB.balanceOf(user);
        vm.stopPrank();

        uint256 received = balanceAfter - balanceBefore;
        console2.log("Swapped:", swapAmount);
        console2.log("Received:", received);

        assertGt(received, 0, "No tokens received from swap");
        // Due to constant product formula, received should be less than input
        assertLt(received, swapAmount, "Received more than swapped");
    }

    /// @notice Test graduation simulation - creating LP from bonding curve reserves
    function test_Fork_GraduationSimulation() public onlyFork {
        // Simulate graduation scenario:
        // - Bonding curve has collected ELTA
        // - Remaining tokens go to LP
        // - LP tokens get locked

        MockERC20 elta = new MockERC20("ELTA", "ELTA", 18);
        MockERC20 appToken = new MockERC20("AppToken", "APP", 18);

        // Simulate graduation amounts
        uint256 eltaForLp = 5000e18; // 5000 ELTA raised
        uint256 tokensForLp = 5_000_000e18; // Remaining tokens

        elta.mint(admin, eltaForLp);
        appToken.mint(admin, tokensForLp);

        vm.startPrank(admin);
        elta.approve(UNISWAP_V2_ROUTER, eltaForLp);
        appToken.approve(UNISWAP_V2_ROUTER, tokensForLp);

        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);

        // Create LP
        (uint256 actualElta, uint256 actualTokens, uint256 lpTokens) = router.addLiquidity(
            address(elta), address(appToken), eltaForLp, tokensForLp, 0, 0, admin, block.timestamp + 1 hours
        );
        vm.stopPrank();

        console2.log("Graduation LP created:");
        console2.log("  ELTA added:", actualElta);
        console2.log("  Tokens added:", actualTokens);
        console2.log("  LP tokens:", lpTokens);

        assertGt(lpTokens, 0, "Graduation failed - no LP tokens");

        // Verify reserves
        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY);
        address pair = factory.getPair(address(elta), address(appToken));
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();

        console2.log("  Reserve 0:", reserve0);
        console2.log("  Reserve 1:", reserve1);

        // Verify price makes sense
        uint256 priceEltaPerToken;
        if (IUniswapV2Pair(pair).token0() == address(elta)) {
            priceEltaPerToken = (uint256(reserve0) * 1e18) / reserve1;
        } else {
            priceEltaPerToken = (uint256(reserve1) * 1e18) / reserve0;
        }

        console2.log("  Price (ELTA/token):", priceEltaPerToken);
        assertGt(priceEltaPerToken, 0, "Invalid price");
    }

    /// @notice Test LP token locking scenario
    function test_Fork_LPLocking() public onlyFork {
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);

        // Create and add liquidity
        uint256 amount = 1000e18;
        tokenA.mint(admin, amount);
        tokenB.mint(admin, amount);

        vm.startPrank(admin);
        tokenA.approve(UNISWAP_V2_ROUTER, amount);
        tokenB.approve(UNISWAP_V2_ROUTER, amount);

        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        (,, uint256 lpTokens) = router.addLiquidity(
            address(tokenA), address(tokenB), amount, amount, 0, 0, admin, block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Get pair address
        IUniswapV2Factory factory = IUniswapV2Factory(UNISWAP_V2_FACTORY);
        address pair = factory.getPair(address(tokenA), address(tokenB));

        // Deploy simple locker
        SimpleLpLocker locker = new SimpleLpLocker(pair, admin, block.timestamp + 365 days);

        // Transfer LP tokens to locker
        vm.prank(admin);
        IUniswapV2Pair(pair).transfer(address(locker), lpTokens);

        // Verify locked
        uint256 lockedBalance = IUniswapV2Pair(pair).balanceOf(address(locker));
        assertEq(lockedBalance, lpTokens, "LP not locked");

        // Try to withdraw before unlock (should fail)
        vm.prank(admin);
        vm.expectRevert("Still locked");
        locker.withdraw();

        // Warp past unlock
        vm.warp(block.timestamp + 366 days);

        // Withdraw should work now
        vm.prank(admin);
        locker.withdraw();

        uint256 adminBalance = IUniswapV2Pair(pair).balanceOf(admin);
        assertEq(adminBalance, lpTokens, "LP not returned");
    }

    /// @notice Test price impact on large swaps
    function test_Fork_PriceImpact() public onlyFork {
        MockERC20 elta = new MockERC20("ELTA", "ELTA", 18);
        MockERC20 appToken = new MockERC20("AppToken", "APP", 18);

        // Create LP with specific ratio
        uint256 eltaLiquidity = 5000e18;
        uint256 tokenLiquidity = 5_000_000e18;

        elta.mint(admin, eltaLiquidity);
        appToken.mint(admin, tokenLiquidity);

        vm.startPrank(admin);
        elta.approve(UNISWAP_V2_ROUTER, eltaLiquidity);
        appToken.approve(UNISWAP_V2_ROUTER, tokenLiquidity);

        IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        router.addLiquidity(
            address(elta), address(appToken), eltaLiquidity, tokenLiquidity, 0, 0, admin, block.timestamp + 1 hours
        );
        vm.stopPrank();

        // Test various swap sizes for price impact
        uint256[] memory swapSizes = new uint256[](4);
        swapSizes[0] = 10e18; // Small: 0.2% of liquidity
        swapSizes[1] = 50e18; // Medium: 1% of liquidity
        swapSizes[2] = 250e18; // Large: 5% of liquidity
        swapSizes[3] = 500e18; // Very large: 10% of liquidity

        console2.log("Price impact analysis:");
        console2.log("ELTA liquidity:", eltaLiquidity);
        console2.log("Token liquidity:", tokenLiquidity);
        console2.log("");

        for (uint256 i = 0; i < swapSizes.length; i++) {
            uint256 swapAmount = swapSizes[i];

            // Get amounts out
            address[] memory path = new address[](2);
            path[0] = address(elta);
            path[1] = address(appToken);

            uint256[] memory amountsOut = router.getAmountsOut(swapAmount, path);
            uint256 tokensOut = amountsOut[1];

            // Calculate effective price
            uint256 effectivePrice = (swapAmount * 1e18) / tokensOut;

            // Calculate expected price without slippage
            uint256 spotPrice = (eltaLiquidity * 1e18) / tokenLiquidity;

            // Calculate price impact
            uint256 priceImpact = ((effectivePrice - spotPrice) * 10000) / spotPrice;

            console2.log("Swap size:", swapAmount / 1e18, "ELTA");
            console2.log("  Tokens out:", tokensOut / 1e18);
            console2.log("  Spot price:", spotPrice);
            console2.log("  Effective price:", effectivePrice);
            console2.log("  Price impact (bps):", priceImpact);
            console2.log("");

            // Price impact should increase with swap size
            if (i > 0) {
                // Larger swaps should have more impact
                assertGt(priceImpact, 0, "No price impact on large swap");
            }
        }
    }
}

// =========== Helper Contracts ===========

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract SimpleLpLocker {
    address public immutable lpToken;
    address public immutable beneficiary;
    uint256 public immutable unlockTime;

    constructor(address _lpToken, address _beneficiary, uint256 _unlockTime) {
        lpToken = _lpToken;
        beneficiary = _beneficiary;
        unlockTime = _unlockTime;
    }

    function withdraw() external {
        require(msg.sender == beneficiary, "Not beneficiary");
        require(block.timestamp >= unlockTime, "Still locked");

        uint256 balance = IUniswapV2Pair(lpToken).balanceOf(address(this));
        IUniswapV2Pair(lpToken).transfer(beneficiary, balance);
    }
}
