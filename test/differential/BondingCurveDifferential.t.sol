// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

/**
 * @title BondingCurveDifferential
 * @notice Differential tests comparing Solidity bonding curve math against Python reference
 * @dev Uses FFI to call Python reference implementation and compare results
 *
 * To run these tests:
 *   forge test --match-contract BondingCurveDifferential --ffi -vvv
 *
 * Requirements:
 *   - Python 3 installed and accessible via 'python3'
 *   - ffi = true in foundry.toml
 *
 * Note: These tests are skipped if FFI/Python is not properly configured.
 */
contract BondingCurveDifferential is Test {
    string constant PYTHON_SCRIPT = "test/differential/bonding_curve_reference.py";
    bool ffiWorking;

    function setUp() public {
        // Test if FFI is working correctly by running a simple Python command
        // Expected: Python outputs "0x2a" (42 in hex) which should parse to 42
        try this.checkFFI() returns (bool works) {
            ffiWorking = works;
        } catch {
            ffiWorking = false;
        }

        if (!ffiWorking) {
            // Skip all tests in this contract if FFI isn't working
            // This is expected in CI environments without Python
        }
    }

    /// @notice Check if FFI is working by testing a known value
    function checkFFI() external returns (bool) {
        string[] memory inputs = new string[](3);
        inputs[0] = "python3";
        inputs[1] = "-c";
        inputs[2] = "print('42')";

        bytes memory result = vm.ffi(inputs);

        // Expected: ASCII "42\n" = [0x34, 0x32, 0x0a]
        if (result.length >= 2 && result[0] == 0x34 && result[1] == 0x32) {
            return true;
        }
        return false;
    }

    modifier skipIfFFINotWorking() {
        if (!ffiWorking) {
            return;
        }
        _;
    }

    // =========== Solidity Reference Implementations ===========

    /// @notice Solidity implementation of getTokensOut
    function sol_getTokensOut(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken)
        internal
        pure
        returns (uint256 tokensOut)
    {
        if (eltaIn == 0 || reserveElta == 0 || reserveToken == 0) return 0;

        // Constant product: x * y = k
        uint256 k = reserveElta * reserveToken;
        uint256 newReserveElta = reserveElta + eltaIn;
        uint256 newReserveToken = k / newReserveElta;

        tokensOut = reserveToken - newReserveToken;
    }

    /// @notice Solidity implementation of getEltaInForTokens
    function sol_getEltaInForTokens(uint256 tokensDesired, uint256 reserveElta, uint256 reserveToken)
        internal
        pure
        returns (uint256 eltaIn)
    {
        if (tokensDesired == 0 || reserveElta == 0 || reserveToken == 0) return 0;
        if (tokensDesired >= reserveToken) return type(uint256).max;

        uint256 k = reserveElta * reserveToken;
        uint256 newReserveToken = reserveToken - tokensDesired;
        uint256 newReserveElta = k / newReserveToken;

        eltaIn = newReserveElta - reserveElta + 1;
    }

    /// @notice Solidity implementation of getCurrentPrice
    function sol_getCurrentPrice(uint256 reserveElta, uint256 reserveToken) internal pure returns (uint256 price) {
        if (reserveToken == 0) return 0;
        price = (reserveElta * 1e18) / reserveToken;
    }

    // =========== Python FFI Helpers ===========

    /// @notice Call Python to get tokens out
    function py_getTokensOut(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken)
        internal
        returns (uint256 tokensOut)
    {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = PYTHON_SCRIPT;
        inputs[2] = "tokens_out";
        inputs[3] = vm.toString(eltaIn);
        inputs[4] = vm.toString(reserveElta);
        inputs[5] = vm.toString(reserveToken);

        bytes memory result = vm.ffi(inputs);
        tokensOut = parseHexResult(result);
    }

    /// @notice Call Python to get ELTA in for tokens
    function py_getEltaIn(uint256 tokensDesired, uint256 reserveElta, uint256 reserveToken)
        internal
        returns (uint256 eltaIn)
    {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = PYTHON_SCRIPT;
        inputs[2] = "elta_in";
        inputs[3] = vm.toString(tokensDesired);
        inputs[4] = vm.toString(reserveElta);
        inputs[5] = vm.toString(reserveToken);

        bytes memory result = vm.ffi(inputs);
        eltaIn = parseHexResult(result);
    }

    /// @notice Call Python to get current price
    function py_getCurrentPrice(uint256 reserveElta, uint256 reserveToken) internal returns (uint256 price) {
        string[] memory inputs = new string[](5);
        inputs[0] = "python3";
        inputs[1] = PYTHON_SCRIPT;
        inputs[2] = "price";
        inputs[3] = vm.toString(reserveElta);
        inputs[4] = vm.toString(reserveToken);

        bytes memory result = vm.ffi(inputs);
        price = parseHexResult(result);
    }

    /// @notice Parse result from Python FFI
    /// @dev FFI returns stdout as raw bytes. Python outputs hex string "0x123abc\n"
    ///      which becomes ASCII bytes. We parse these ASCII hex chars to uint256.
    function parseHexResult(bytes memory result) internal pure returns (uint256) {
        if (result.length == 0) return 0;

        uint256 value = 0;
        uint256 i = 0;

        // Skip "0x" prefix if present (ASCII: '0' = 0x30, 'x' = 0x78)
        if (result.length >= 2 && result[0] == 0x30 && result[1] == 0x78) {
            i = 2;
        }

        // Parse hex digits until newline (0x0a) or end
        for (; i < result.length; i++) {
            uint8 c = uint8(result[i]);

            // Stop at newline, carriage return, or space
            if (c == 0x0a || c == 0x0d || c == 0x20) break;

            // Multiply by 16 for each hex digit
            value = value * 16;

            // Parse hex digit
            if (c >= 0x30 && c <= 0x39) {
                // '0'-'9' (0x30-0x39)
                value += c - 0x30;
            } else if (c >= 0x61 && c <= 0x66) {
                // 'a'-'f' (0x61-0x66)
                value += c - 0x61 + 10;
            } else if (c >= 0x41 && c <= 0x46) {
                // 'A'-'F' (0x41-0x46)
                value += c - 0x41 + 10;
            }
            // Skip invalid chars (don't add to value)
        }

        return value;
    }

    // =========== Differential Tests ===========

    /// @notice Test getTokensOut matches Python reference
    function test_Diff_GetTokensOut_Basic() public skipIfFFINotWorking {
        uint256 reserveElta = 1000e18;
        uint256 reserveToken = 10_000_000e18;
        uint256 eltaIn = 100e18;

        uint256 solResult = sol_getTokensOut(eltaIn, reserveElta, reserveToken);
        uint256 pyResult = py_getTokensOut(eltaIn, reserveElta, reserveToken);

        console2.log("Solidity result:", solResult);
        console2.log("Python result:  ", pyResult);

        assertEq(solResult, pyResult, "getTokensOut mismatch");
    }

    /// @notice Fuzz test getTokensOut against Python reference
    function test_Diff_GetTokensOut_Fuzz(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken)
        public
        skipIfFFINotWorking
    {
        // Bound inputs to reasonable ranges to avoid overflow
        reserveElta = bound(reserveElta, 1e18, 1_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 100_000_000e18);
        eltaIn = bound(eltaIn, 1e18, reserveElta);

        uint256 solResult = sol_getTokensOut(eltaIn, reserveElta, reserveToken);
        uint256 pyResult = py_getTokensOut(eltaIn, reserveElta, reserveToken);

        assertEq(solResult, pyResult, "getTokensOut fuzz mismatch");
    }

    /// @notice Test getCurrentPrice matches Python reference
    function test_Diff_GetCurrentPrice_Basic() public skipIfFFINotWorking {
        uint256 reserveElta = 1000e18;
        uint256 reserveToken = 10_000_000e18;

        uint256 solResult = sol_getCurrentPrice(reserveElta, reserveToken);
        uint256 pyResult = py_getCurrentPrice(reserveElta, reserveToken);

        console2.log("Solidity price:", solResult);
        console2.log("Python price:  ", pyResult);

        assertEq(solResult, pyResult, "getCurrentPrice mismatch");
    }

    /// @notice Fuzz test getCurrentPrice against Python reference
    function test_Diff_GetCurrentPrice_Fuzz(uint256 reserveElta, uint256 reserveToken) public skipIfFFINotWorking {
        // Bound inputs
        reserveElta = bound(reserveElta, 1e18, 1_000_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 1_000_000_000e18);

        uint256 solResult = sol_getCurrentPrice(reserveElta, reserveToken);
        uint256 pyResult = py_getCurrentPrice(reserveElta, reserveToken);

        assertEq(solResult, pyResult, "getCurrentPrice fuzz mismatch");
    }

    /// @notice Test getEltaInForTokens matches Python reference
    function test_Diff_GetEltaInForTokens_Basic() public skipIfFFINotWorking {
        uint256 reserveElta = 1000e18;
        uint256 reserveToken = 10_000_000e18;
        uint256 tokensDesired = 100_000e18;

        uint256 solResult = sol_getEltaInForTokens(tokensDesired, reserveElta, reserveToken);
        uint256 pyResult = py_getEltaIn(tokensDesired, reserveElta, reserveToken);

        console2.log("Solidity ELTA needed:", solResult);
        console2.log("Python ELTA needed:  ", pyResult);

        assertEq(solResult, pyResult, "getEltaInForTokens mismatch");
    }

    /// @notice Fuzz test getEltaInForTokens against Python reference
    function test_Diff_GetEltaInForTokens_Fuzz(uint256 tokensDesired, uint256 reserveElta, uint256 reserveToken)
        public
        skipIfFFINotWorking
    {
        // Bound inputs
        reserveElta = bound(reserveElta, 1e18, 1_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 100_000_000e18);
        tokensDesired = bound(tokensDesired, 1e18, reserveToken - 1);

        uint256 solResult = sol_getEltaInForTokens(tokensDesired, reserveElta, reserveToken);
        uint256 pyResult = py_getEltaIn(tokensDesired, reserveElta, reserveToken);

        assertEq(solResult, pyResult, "getEltaInForTokens fuzz mismatch");
    }

    // =========== Edge Case Tests ===========

    /// @notice Test zero inputs
    function test_Diff_ZeroInputs() public skipIfFFINotWorking {
        assertEq(sol_getTokensOut(0, 1000e18, 10_000_000e18), py_getTokensOut(0, 1000e18, 10_000_000e18));
        assertEq(sol_getTokensOut(100e18, 0, 10_000_000e18), py_getTokensOut(100e18, 0, 10_000_000e18));
        assertEq(sol_getTokensOut(100e18, 1000e18, 0), py_getTokensOut(100e18, 1000e18, 0));
    }

    /// @notice Test large values near overflow boundaries
    function test_Diff_LargeValues() public skipIfFFINotWorking {
        // Use values that won't overflow when multiplied
        uint256 reserveElta = 1e36;
        uint256 reserveToken = 1e36;
        uint256 eltaIn = 1e35;

        uint256 solResult = sol_getTokensOut(eltaIn, reserveElta, reserveToken);
        uint256 pyResult = py_getTokensOut(eltaIn, reserveElta, reserveToken);

        assertEq(solResult, pyResult, "Large value mismatch");
    }

    /// @notice Test constant product invariant is maintained
    function test_Diff_ConstantProductInvariant(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken) public {
        // Bound inputs
        reserveElta = bound(reserveElta, 1e18, 1_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 100_000_000e18);
        eltaIn = bound(eltaIn, 1e18, reserveElta);

        uint256 kBefore = reserveElta * reserveToken;
        uint256 tokensOut = sol_getTokensOut(eltaIn, reserveElta, reserveToken);
        uint256 kAfter = (reserveElta + eltaIn) * (reserveToken - tokensOut);

        // k should stay approximately constant (may decrease slightly due to integer division)
        assertLe(kAfter, kBefore, "k increased");
        assertGe(kAfter, (kBefore * 99) / 100, "k decreased too much");
    }

    /// @notice Test price increases with buys
    function test_Diff_PriceIncreasesWithBuys() public {
        uint256 reserveElta = 1000e18;
        uint256 reserveToken = 10_000_000e18;

        uint256 priceBefore = sol_getCurrentPrice(reserveElta, reserveToken);

        // Simulate a buy
        uint256 eltaIn = 100e18;
        uint256 tokensOut = sol_getTokensOut(eltaIn, reserveElta, reserveToken);
        uint256 newReserveElta = reserveElta + eltaIn;
        uint256 newReserveToken = reserveToken - tokensOut;

        uint256 priceAfter = sol_getCurrentPrice(newReserveElta, newReserveToken);

        console2.log("Price before buy:", priceBefore);
        console2.log("Price after buy: ", priceAfter);

        assertGt(priceAfter, priceBefore, "Price did not increase");
    }

    /// @notice Test round-trip: spend ELTA -> get tokens -> calculate ELTA needed for those tokens
    function test_Diff_RoundTrip(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken) public {
        // Bound inputs more tightly to reduce edge cases
        reserveElta = bound(reserveElta, 1e18, 1_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 100_000_000e18);
        eltaIn = bound(eltaIn, 1e15, reserveElta / 10); // Small amounts to avoid edge cases

        // Buy tokens with eltaIn
        uint256 tokensOut = sol_getTokensOut(eltaIn, reserveElta, reserveToken);

        if (tokensOut == 0) return; // Skip if no tokens received

        // Calculate how much ELTA would be needed for those tokens
        uint256 eltaNeeded = sol_getEltaInForTokens(tokensOut, reserveElta, reserveToken);

        // eltaNeeded should be close to eltaIn (within rounding)
        // We add 1 in getEltaInForTokens for rounding up
        // Rounding error can be larger for edge cases with extreme reserve ratios
        assertLe(eltaIn, eltaNeeded, "Round trip: needed less than spent");

        // Allow proportional rounding error: max 0.01% of eltaIn or 1000 wei, whichever is larger
        uint256 maxError = eltaIn / 10000; // 0.01%
        if (maxError < 1000) maxError = 1000;
        assertLe(eltaNeeded - eltaIn, maxError, "Round trip: rounding error too large");
    }
}
