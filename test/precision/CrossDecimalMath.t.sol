// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {TreasuryUSDCVault} from "../../src/fees/TreasuryUSDCVault.sol";
import {PrecisionFixtures} from "../fixtures/PrecisionFixtures.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock USDC with 6 decimals
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000_000e6); // 1B USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock 8-decimal token (like WBTC)
contract Mock8DecimalToken is ERC20 {
    constructor() ERC20("Mock WBTC", "WBTC") {
        _mint(msg.sender, 21_000_000e8);
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock Uniswap Router for swap simulation
contract MockSwapRouter {
    ELTA public elta;
    MockUSDC public usdc;
    uint256 public exchangeRate; // USDC per ELTA (scaled by 1e6)

    constructor(address _elta, address _usdc, uint256 _rate) {
        elta = ELTA(_elta);
        usdc = MockUSDC(_usdc);
        exchangeRate = _rate;
    }

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external {
        require(path[0] == address(elta) && path[1] == address(usdc), "Invalid path");

        // Calculate USDC output: eltaAmount * rate / 1e18 (ELTA has 18 decimals)
        // rate is USDC per ELTA, with 6 decimals
        uint256 usdcOut = (amountIn * exchangeRate) / 1e18;

        // Transfer
        elta.transferFrom(msg.sender, address(this), amountIn);
        usdc.transfer(to, usdcOut);
    }

    function factory() external pure returns (address) {
        return address(0);
    }
}

/**
 * @title CrossDecimalMath
 * @notice Tests for precision issues with mixed-decimal token arithmetic
 * @dev ELTA uses 18 decimals, USDC uses 6 decimals
 *
 * Key test scenarios:
 * - ELTA to USDC conversion precision
 * - Dust amounts that round to zero
 * - Large amounts near overflow
 * - Round-trip conversion accuracy
 */
contract CrossDecimalMath is Test, PrecisionFixtures {
    ELTA public elta;
    MockUSDC public usdc;
    Mock8DecimalToken public wbtc;
    FeeManager public feeManager;
    TreasuryUSDCVault public treasuryVault;
    MockSwapRouter public swapRouter;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public appRewards = makeAddr("appRewards");
    address public veRewards = makeAddr("veRewards");
    address public governance = makeAddr("governance");

    // Exchange rate: 1 ELTA = $0.10 USDC (0.1e6 USDC)
    uint256 public constant EXCHANGE_RATE = 0.1e6;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        elta = new ELTA(treasury);
        usdc = new MockUSDC();
        wbtc = new Mock8DecimalToken();

        // Deploy swap router
        swapRouter = new MockSwapRouter(address(elta), address(usdc), EXCHANGE_RATE);

        // Fund swap router with USDC for swaps
        usdc.transfer(address(swapRouter), 100_000_000e6);

        // Deploy TreasuryUSDCVault
        treasuryVault = new TreasuryUSDCVault(address(usdc), admin, governance, address(0));

        // Deploy FeeManager
        feeManager = new FeeManager(
            address(elta), address(usdc), admin, governance, appRewards, veRewards, address(treasuryVault), 1 days
        );

        // Configure FeeManager swap
        feeManager.setSwapRouter(address(swapRouter));

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC DECIMAL CONVERSION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test 18 to 6 decimal conversion
    function test_Decimal_18To6Conversion() public pure {
        // 1 ELTA (1e18) at rate 0.1 USDC/ELTA should be 0.1 USDC (1e5)
        uint256 eltaAmount = 1e18;
        uint256 rate = 0.1e6; // 0.1 USDC per ELTA

        // Formula: eltaAmount * rate / 1e18
        uint256 usdcOut = (eltaAmount * rate) / 1e18;

        assertEq(usdcOut, 100000, "1 ELTA should convert to 0.1 USDC");
    }

    /// @notice Test 6 to 18 decimal conversion
    function test_Decimal_6To18Conversion() public pure {
        // 1 USDC (1e6) to ELTA scale (1e18)
        uint256 usdcAmount = 1e6;

        // Simple scaling
        uint256 eltaScale = usdcAmount * 1e12;

        assertEq(eltaScale, 1e18, "1 USDC should scale to 1e18");
    }

    /// @notice Test using fixtures for various amounts
    function test_Decimal_FixtureAmounts() public view {
        for (uint256 i = 0; i < fixtureElta18Decimals.length; i++) {
            uint256 eltaAmount = fixtureElta18Decimals[i];
            uint256 usdcOut = convert18To6(eltaAmount);

            console2.log("ELTA amount:", eltaAmount);
            console2.log("USDC equivalent:", usdcOut);

            // Verify conversion doesn't overflow
            assertLe(usdcOut, type(uint256).max / 1e12, "Conversion overflow risk");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DUST AMOUNT CONVERSION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test dust ELTA amounts that round to zero USDC
    function test_Decimal_DustRoundsToZero() public pure {
        // At 0.1 USDC/ELTA rate, amounts below 10^13 wei round to 0
        uint256[] memory dustAmounts = new uint256[](5);
        dustAmounts[0] = 1; // 1 wei
        dustAmounts[1] = 1e6; // 1M wei
        dustAmounts[2] = 1e9; // 1 gwei
        dustAmounts[3] = 1e12; // Just below threshold

        for (uint256 i = 0; i < dustAmounts.length; i++) {
            uint256 eltaAmount = dustAmounts[i];
            uint256 rate = 0.1e6;

            uint256 dustUsdcOut = (eltaAmount * rate) / 1e18;

            // All these should round to 0
            assertEq(dustUsdcOut, 0, "Dust should round to 0");
        }

        // Exactly 1e13 should give 1 wei USDC (0.000001 USDC)
        uint256 threshold = 1e13;
        uint256 thresholdUsdcOut = (threshold * 0.1e6) / 1e18;
        assertEq(thresholdUsdcOut, 1, "Threshold should give 1 USDC wei");
    }

    /// @notice Test minimum ELTA to get 1 USDC wei
    function test_Decimal_MinimumForOneUsdcWei() public pure {
        uint256 rate = 0.1e6; // 0.1 USDC per ELTA

        // Find minimum ELTA to get 1 USDC wei
        // usdcOut = eltaIn * rate / 1e18 >= 1
        // eltaIn >= 1e18 / rate
        uint256 minElta = 1e18 / rate;

        uint256 usdcOut = (minElta * rate) / 1e18;
        assertEq(usdcOut, 1, "Min ELTA should give 1 USDC wei");

        // One less should give 0
        uint256 belowMin = minElta - 1;
        uint256 usdcOutBelow = (belowMin * rate) / 1e18;
        assertEq(usdcOutBelow, 0, "Below min should give 0");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LARGE AMOUNT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test large ELTA amounts don't overflow
    function test_Decimal_LargeAmountNoOverflow() public pure {
        uint256 maxElta = 77_000_000e18; // Max ELTA supply
        uint256 rate = 100e6; // High rate: $100 per ELTA

        // Should not overflow
        uint256 usdcOut = (maxElta * rate) / 1e18;

        // Expected: 77M * $100 = $7.7B = 7.7e15 USDC wei
        assertEq(usdcOut, 7_700_000_000_000_000, "Large conversion incorrect");
    }

    /// @notice Test overflow boundary
    function test_Decimal_OverflowBoundary() public view {
        // Find max safe ELTA amount for given rate
        uint256 rate = 1e6; // $1 per ELTA
        uint256 maxSafeElta = type(uint256).max / rate;

        console2.log("Max safe ELTA:", maxSafeElta);

        // Verify we can calculate at max safe
        uint256 usdcOut = (maxSafeElta * rate) / 1e18;
        assertGt(usdcOut, 0, "Should produce non-zero output");

        // Verify overflow detection
        assertTrue(wouldOverflow(maxSafeElta + 1, rate), "Should detect overflow");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROUND-TRIP CONVERSION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test ELTA -> USDC -> ELTA (conceptual) precision loss
    function test_Decimal_RoundTripPrecisionLoss() public pure {
        // Convert ELTA to USDC then back to ELTA scale
        uint256 eltaOriginal = 12345678901234567890; // ~12.35 ELTA
        uint256 rate = 0.1e6;

        // ELTA to USDC
        uint256 usdcConverted = (eltaOriginal * rate) / 1e18;

        // USDC back to ELTA scale (assuming same rate)
        // eltaRecovered = usdcConverted * 1e18 / rate
        uint256 eltaRecovered = (usdcConverted * 1e18) / rate;

        console2.log("Original ELTA:", eltaOriginal);
        console2.log("USDC:", usdcConverted);
        console2.log("Recovered ELTA:", eltaRecovered);

        // Precision loss
        uint256 loss = eltaOriginal > eltaRecovered ? eltaOriginal - eltaRecovered : eltaRecovered - eltaOriginal;

        console2.log("Precision loss:", loss);

        // Loss should be bounded by conversion granularity
        assertLe(loss, 1e13, "Too much precision loss");
    }

    /// @notice Fuzz test round-trip conversion
    function testFuzz_Decimal_RoundTrip(uint256 eltaAmount) public pure {
        // Bound to reasonable amounts
        eltaAmount = bound(eltaAmount, 1e13, 10_000_000e18);
        uint256 rate = 0.1e6;

        // Forward conversion
        uint256 usdcAmount = (eltaAmount * rate) / 1e18;

        // Back conversion
        uint256 eltaRecovered = (usdcAmount * 1e18) / rate;

        // Original should be >= recovered (always lose, never gain)
        assertGe(eltaAmount, eltaRecovered, "Should not gain precision");

        // Loss bounded
        uint256 loss = eltaAmount - eltaRecovered;
        assertLe(loss, 1e13, "Precision loss too large");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SWAP INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test actual swap with mock router
    function test_Swap_BasicConversion() public {
        uint256 eltaAmount = 1000e18;

        vm.prank(treasury);
        elta.transfer(address(this), eltaAmount);

        elta.approve(address(swapRouter), eltaAmount);

        uint256 usdcBefore = usdc.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(elta);
        path[1] = address(usdc);

        swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            eltaAmount, 0, path, address(this), block.timestamp
        );

        uint256 usdcAfter = usdc.balanceOf(address(this));
        uint256 usdcReceived = usdcAfter - usdcBefore;

        // At 0.1 USDC/ELTA, 1000 ELTA = 100 USDC
        assertEq(usdcReceived, 100e6, "Swap conversion incorrect");
    }

    /// @notice Test swap with dust amounts
    function test_Swap_DustAmount() public {
        uint256 eltaAmount = 1e12; // Dust amount

        vm.prank(treasury);
        elta.transfer(address(this), eltaAmount);

        elta.approve(address(swapRouter), eltaAmount);

        uint256 usdcBefore = usdc.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(elta);
        path[1] = address(usdc);

        swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            eltaAmount, 0, path, address(this), block.timestamp
        );

        uint256 usdcAfter = usdc.balanceOf(address(this));
        uint256 usdcReceived = usdcAfter - usdcBefore;

        // Should receive 0 (dust rounds down)
        assertEq(usdcReceived, 0, "Dust should give 0 USDC");
    }

    /// @notice Test swap at varying exchange rates
    function test_Swap_VaryingRates() public {
        uint256 eltaAmount = 100e18;
        uint256[] memory rates = new uint256[](5);
        rates[0] = 0.01e6; // $0.01 per ELTA
        rates[1] = 0.1e6; // $0.10 per ELTA
        rates[2] = 1e6; // $1 per ELTA
        rates[3] = 10e6; // $10 per ELTA
        rates[4] = 100e6; // $100 per ELTA

        for (uint256 i = 0; i < rates.length; i++) {
            swapRouter.setExchangeRate(rates[i]);

            // Calculate expected USDC
            uint256 expectedUsdc = (eltaAmount * rates[i]) / 1e18;

            // Actually swap
            vm.prank(treasury);
            elta.transfer(address(this), eltaAmount);

            elta.approve(address(swapRouter), eltaAmount);

            uint256 usdcBefore = usdc.balanceOf(address(this));

            address[] memory path = new address[](2);
            path[0] = address(elta);
            path[1] = address(usdc);

            swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                eltaAmount, 0, path, address(this), block.timestamp
            );

            uint256 usdcReceived = usdc.balanceOf(address(this)) - usdcBefore;

            console2.log("Rate:", rates[i]);
            console2.log("Expected USDC:", expectedUsdc);
            console2.log("Received USDC:", usdcReceived);

            assertEq(usdcReceived, expectedUsdc, "Swap amount mismatch");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MIXED DECIMAL TOKEN TESTS (8 decimals)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test 18 to 8 decimal conversion
    function test_Decimal_18To8Conversion() public pure {
        // ELTA (18) to WBTC-scale (8)
        uint256 elta18 = 1e18;
        uint256 btc8 = elta18 / 1e10;

        assertEq(btc8, 1e8, "18 to 8 conversion");
    }

    /// @notice Test 6 to 8 decimal conversion
    function test_Decimal_6To8Conversion() public pure {
        // USDC (6) to WBTC-scale (8)
        uint256 usdc6 = 1e6;
        uint256 btc8 = usdc6 * 100; // 1e6 * 1e2 = 1e8

        assertEq(btc8, 1e8, "6 to 8 conversion");
    }

    /// @notice Test precision loss across different decimals
    function testFuzz_Decimal_MixedConversions(uint256 amount) public pure {
        // Bound to prevent overflow
        amount = bound(amount, 1, 1e30);

        // 18 -> 6 -> 18 round trip
        uint256 to6 = amount / 1e12;
        uint256 back18 = to6 * 1e12;
        assertLe(back18, amount, "Should not gain in 18->6->18");

        // 18 -> 8 -> 18 round trip
        uint256 to8 = amount / 1e10;
        uint256 back18_from8 = to8 * 1e10;
        assertLe(back18_from8, amount, "Should not gain in 18->8->18");

        // 6 -> 8 is lossy going up (multiply by 100)
        // 8 -> 6 is lossy going down (divide by 100)
    }
}
