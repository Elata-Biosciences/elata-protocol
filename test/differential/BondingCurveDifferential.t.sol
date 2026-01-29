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
 */
contract BondingCurveDifferential is Test {
    string constant PYTHON_SCRIPT = "test/differential/bonding_curve_reference.py";

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

    /// @notice Parse hex string result from Python
    function parseHexResult(bytes memory result) internal pure returns (uint256) {
        // Result is hex string like "0x123abc\n"
        // Need to parse it to uint256
        uint256 value = 0;
        uint256 start = 0;

        // Skip "0x" prefix if present
        if (result.length >= 2 && result[0] == "0" && result[1] == "x") {
            start = 2;
        }

        for (uint256 i = start; i < result.length; i++) {
            uint8 c = uint8(result[i]);

            // Stop at newline or other non-hex
            if (c == 10 || c == 13 || c == 32) break;

            value *= 16;

            if (c >= 48 && c <= 57) {
                // '0'-'9'
                value += c - 48;
            } else if (c >= 97 && c <= 102) {
                // 'a'-'f'
                value += c - 87;
            } else if (c >= 65 && c <= 70) {
                // 'A'-'F'
                value += c - 55;
            }
        }

        return value;
    }

    // =========== Differential Tests ===========

    /// @notice Test getTokensOut matches Python reference
    function test_Diff_GetTokensOut_Basic() public {
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
    function test_Diff_GetTokensOut_Fuzz(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken) public {
        // Bound inputs to reasonable ranges to avoid overflow
        reserveElta = bound(reserveElta, 1e18, 1_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 100_000_000e18);
        eltaIn = bound(eltaIn, 1e18, reserveElta);

        uint256 solResult = sol_getTokensOut(eltaIn, reserveElta, reserveToken);
        uint256 pyResult = py_getTokensOut(eltaIn, reserveElta, reserveToken);

        assertEq(solResult, pyResult, "getTokensOut fuzz mismatch");
    }

    /// @notice Test getCurrentPrice matches Python reference
    function test_Diff_GetCurrentPrice_Basic() public {
        uint256 reserveElta = 1000e18;
        uint256 reserveToken = 10_000_000e18;

        uint256 solResult = sol_getCurrentPrice(reserveElta, reserveToken);
        uint256 pyResult = py_getCurrentPrice(reserveElta, reserveToken);

        console2.log("Solidity price:", solResult);
        console2.log("Python price:  ", pyResult);

        assertEq(solResult, pyResult, "getCurrentPrice mismatch");
    }

    /// @notice Fuzz test getCurrentPrice against Python reference
    function test_Diff_GetCurrentPrice_Fuzz(uint256 reserveElta, uint256 reserveToken) public {
        // Bound inputs
        reserveElta = bound(reserveElta, 1e18, 1_000_000_000e18);
        reserveToken = bound(reserveToken, 1e18, 1_000_000_000e18);

        uint256 solResult = sol_getCurrentPrice(reserveElta, reserveToken);
        uint256 pyResult = py_getCurrentPrice(reserveElta, reserveToken);

        assertEq(solResult, pyResult, "getCurrentPrice fuzz mismatch");
    }

    /// @notice Test getEltaInForTokens matches Python reference
    function test_Diff_GetEltaInForTokens_Basic() public {
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
    function test_Diff_ZeroInputs() public {
        assertEq(sol_getTokensOut(0, 1000e18, 10_000_000e18), py_getTokensOut(0, 1000e18, 10_000_000e18));
        assertEq(sol_getTokensOut(100e18, 0, 10_000_000e18), py_getTokensOut(100e18, 0, 10_000_000e18));
        assertEq(sol_getTokensOut(100e18, 1000e18, 0), py_getTokensOut(100e18, 1000e18, 0));
    }

    /// @notice Test large values near overflow boundaries
    function test_Diff_LargeValues() public {
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
        // Bound inputs
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
        assertLe(eltaIn, eltaNeeded, "Round trip: needed less than spent");
        assertLe(eltaNeeded - eltaIn, 2, "Round trip: rounding error too large");
    }
}
