// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title BondingCurveTable
 * @notice Table-driven tests for bonding curve calculations
 * @dev Tests constant product AMM formula with known expected outputs
 *
 * Formula: x * y = k (constant product)
 * Buy: newY = k / (x + eltaIn), tokensOut = y - newY
 * Price: price = x / y * 1e18
 */
contract BondingCurveTable is Test {
    // =========== Tokens Out Tests ===========

    struct TokensOutTestCase {
        string name;
        uint256 eltaIn;
        uint256 reserveElta;
        uint256 reserveToken;
        uint256 expectedTokensOut;
    }

    function getTokensOutTestCases() internal pure returns (TokensOutTestCase[] memory) {
        TokensOutTestCase[] memory cases = new TokensOutTestCase[](12);

        // Case 1: Basic buy - 10% of reserve
        cases[0] = TokensOutTestCase({
            name: "10% reserve buy",
            eltaIn: 100e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // k = 1000 * 10M = 10B (in 1e36)
            // newReserveElta = 1100e18
            // newReserveToken = k / newReserveElta = 9090909090909090909090909 (rounded down)
            // tokensOut = 10_000_000e18 - 9090909090909090909090909 = 909090909090909090909091
            expectedTokensOut: 909090909090909090909091
        });

        // Case 2: Small buy - 1% of reserve
        cases[1] = TokensOutTestCase({
            name: "1% reserve buy",
            eltaIn: 10e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // k = 10_000_000e36 (1000e18 * 10_000_000e18)
            // newReserveElta = 1010e18
            // newReserveToken = k / newReserveElta = 9900990099009900990099009 (rounded down)
            // tokensOut = 10_000_000e18 - 9900990099009900990099009 = 99009900990099009900991
            expectedTokensOut: 99009900990099009900991
        });

        // Case 3: Large buy - 50% of reserve
        cases[2] = TokensOutTestCase({
            name: "50% reserve buy",
            eltaIn: 500e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // k = 10_000_000e36
            // newReserveElta = 1500e18
            // newReserveToken = k / newReserveElta = 6666666666666666666666666 (rounded down)
            // tokensOut = 10_000_000e18 - 6666666666666666666666666 = 3333333333333333333333334
            expectedTokensOut: 3333333333333333333333334
        });

        // Case 4: Very small buy - 1 token
        cases[3] = TokensOutTestCase({
            name: "Minimum buy 1 token",
            eltaIn: 1e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // k = 10_000_000e36
            // newReserveElta = 1001e18
            // newReserveToken = k / newReserveElta = 9990009990009990009990009 (rounded down)
            // tokensOut = 10_000_000e18 - 9990009990009990009990009 = 9990009990009990009991
            expectedTokensOut: 9990009990009990009991
        });

        // Case 5: Equal reserves
        cases[4] = TokensOutTestCase({
            name: "Equal reserves",
            eltaIn: 100e18,
            reserveElta: 1000e18,
            reserveToken: 1000e18,
            // k = 1000e18 * 1000e18 = 1e42
            // newReserveElta = 1100e18
            // newReserveToken = k / newReserveElta = 909090909090909090909 (rounded down)
            // tokensOut = 1000e18 - 909090909090909090909 = 90909090909090909091
            expectedTokensOut: 90909090909090909091
        });

        // Case 6: High ELTA reserve
        cases[5] = TokensOutTestCase({
            name: "High ELTA reserve",
            eltaIn: 1000e18,
            reserveElta: 10_000e18,
            reserveToken: 1_000_000e18,
            // k = 10_000e18 * 1_000_000e18 = 1e46
            // newReserveElta = 11_000e18
            // newReserveToken = k / newReserveElta = 909090909090909090909090 (rounded down)
            // tokensOut = 1_000_000e18 - 909090909090909090909090 = 90909090909090909090910
            expectedTokensOut: 90909090909090909090910
        });

        // Case 7: Zero ELTA in
        cases[6] = TokensOutTestCase({
            name: "Zero ELTA in", eltaIn: 0, reserveElta: 1000e18, reserveToken: 10_000_000e18, expectedTokensOut: 0
        });

        // Case 8: Zero ELTA reserve
        cases[7] = TokensOutTestCase({
            name: "Zero ELTA reserve", eltaIn: 100e18, reserveElta: 0, reserveToken: 10_000_000e18, expectedTokensOut: 0
        });

        // Case 9: Zero token reserve
        cases[8] = TokensOutTestCase({
            name: "Zero token reserve", eltaIn: 100e18, reserveElta: 1000e18, reserveToken: 0, expectedTokensOut: 0
        });

        // Case 10: Buy entire reserve (should leave 1)
        cases[9] = TokensOutTestCase({
            name: "Buy with ELTA = reserve",
            eltaIn: 1000e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // newReserveElta = 2000
            // newReserveToken = 10B / 2000 = 5M
            // tokensOut = 5M
            expectedTokensOut: 5_000_000e18
        });

        // Case 11: Graduation threshold simulation
        cases[10] = TokensOutTestCase({
            name: "Near graduation",
            eltaIn: 4000e18, // Buying to reach 5000 ELTA target
            reserveElta: 1000e18,
            reserveToken: 5_000_000e18,
            // k = 5B
            // newReserveElta = 5000
            // newReserveToken = 5B / 5000 = 1M
            // tokensOut = 4M
            expectedTokensOut: 4_000_000e18
        });

        // Case 12: Very large amounts
        cases[11] = TokensOutTestCase({
            name: "Large amounts",
            eltaIn: 1_000_000e18,
            reserveElta: 10_000_000e18,
            reserveToken: 100_000_000e18,
            // k = 10_000_000e18 * 100_000_000e18 = 1e51
            // newReserveElta = 11_000_000e18
            // newReserveToken = k / newReserveElta = 90909090909090909090909090 (rounded down)
            // tokensOut = 100_000_000e18 - 90909090909090909090909090 = 9090909090909090909090910
            expectedTokensOut: 9090909090909090909090910
        });

        return cases;
    }

    function test_Table_TokensOut() public pure {
        TokensOutTestCase[] memory cases = getTokensOutTestCases();

        for (uint256 i = 0; i < cases.length; i++) {
            TokensOutTestCase memory tc = cases[i];

            uint256 tokensOut = getTokensOut(tc.eltaIn, tc.reserveElta, tc.reserveToken);

            assertEq(tokensOut, tc.expectedTokensOut, string.concat(tc.name, ": tokens out mismatch"));
        }
    }

    // =========== Price Tests ===========

    struct PriceTestCase {
        string name;
        uint256 reserveElta;
        uint256 reserveToken;
        uint256 expectedPrice; // Scaled by 1e18
    }

    function getPriceTestCases() internal pure returns (PriceTestCase[] memory) {
        PriceTestCase[] memory cases = new PriceTestCase[](8);

        // Case 1: 1:10000 ratio
        cases[0] = PriceTestCase({
            name: "1:10000 ratio",
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // price = 1000e18 * 1e18 / 10_000_000e18 = 0.0001e18 = 100000000000000
            expectedPrice: 100000000000000 // 0.0001 ELTA per token
        });

        // Case 2: 1:1 ratio
        cases[1] = PriceTestCase({
            name: "1:1 ratio",
            reserveElta: 1000e18,
            reserveToken: 1000e18,
            expectedPrice: 1e18 // 1 ELTA per token
        });

        // Case 3: 10:1 ratio (expensive tokens)
        cases[2] = PriceTestCase({
            name: "10:1 ratio",
            reserveElta: 10000e18,
            reserveToken: 1000e18,
            expectedPrice: 10e18 // 10 ELTA per token
        });

        // Case 4: Post-graduation price
        cases[3] = PriceTestCase({
            name: "Post graduation",
            reserveElta: 5000e18,
            reserveToken: 1_000_000e18,
            expectedPrice: 5000000000000000 // 0.005 ELTA per token
        });

        // Case 5: Initial low price
        cases[4] = PriceTestCase({
            name: "Initial low price",
            reserveElta: 100e18,
            reserveToken: 10_000_000e18,
            expectedPrice: 10000000000000 // 0.00001 ELTA per token
        });

        // Case 6: Zero token reserve
        cases[5] = PriceTestCase({name: "Zero token reserve", reserveElta: 1000e18, reserveToken: 0, expectedPrice: 0});

        // Case 7: Very small token reserve (high price)
        cases[6] = PriceTestCase({
            name: "Very small token reserve",
            reserveElta: 1000e18,
            reserveToken: 100e18,
            expectedPrice: 10e18 // 10 ELTA per token
        });

        // Case 8: Large values
        cases[7] = PriceTestCase({
            name: "Large reserves",
            reserveElta: 1_000_000e18,
            reserveToken: 100_000_000e18,
            expectedPrice: 10000000000000000 // 0.01 ELTA per token
        });

        return cases;
    }

    function test_Table_Price() public pure {
        PriceTestCase[] memory cases = getPriceTestCases();

        for (uint256 i = 0; i < cases.length; i++) {
            PriceTestCase memory tc = cases[i];

            uint256 price = getCurrentPrice(tc.reserveElta, tc.reserveToken);

            assertEq(price, tc.expectedPrice, string.concat(tc.name, ": price mismatch"));
        }
    }

    // =========== ELTA In For Tokens Tests ===========

    struct EltaInTestCase {
        string name;
        uint256 tokensDesired;
        uint256 reserveElta;
        uint256 reserveToken;
        uint256 expectedEltaIn;
    }

    function getEltaInTestCases() internal pure returns (EltaInTestCase[] memory) {
        EltaInTestCase[] memory cases = new EltaInTestCase[](6);

        // Case 1: Buy 10% of tokens
        cases[0] = EltaInTestCase({
            name: "Buy 10% of tokens",
            tokensDesired: 1_000_000e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // k = 10B
            // newReserveToken = 9M
            // newReserveElta = 10B / 9M = 1111.11
            // eltaIn = 1111.11 - 1000 + 1 = 112.11
            expectedEltaIn: 111111111111111111112
        });

        // Case 2: Buy small amount
        cases[1] = EltaInTestCase({
            name: "Buy 1% of tokens",
            tokensDesired: 100_000e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // newReserveToken = 9.9M
            // newReserveElta = 10B / 9.9M = 1010.1
            // eltaIn = 10.1 + 1 = 11.1
            expectedEltaIn: 10101010101010101011
        });

        // Case 3: Buy half
        cases[2] = EltaInTestCase({
            name: "Buy 50% of tokens",
            tokensDesired: 5_000_000e18,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            // k = 10_000_000e36 (1000e18 * 10_000_000e18)
            // newReserveToken = 5_000_000e18
            // newReserveElta = k / newReserveToken = 2000e18
            // eltaIn = newReserveElta - reserveElta + 1 = 2000e18 - 1000e18 + 1 = 1000e18 + 1
            expectedEltaIn: 1000000000000000000001
        });

        // Case 4: Zero tokens desired
        cases[3] = EltaInTestCase({
            name: "Zero tokens desired",
            tokensDesired: 0,
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            expectedEltaIn: 0
        });

        // Case 5: More than reserve (should return max)
        cases[4] = EltaInTestCase({
            name: "More than reserve",
            tokensDesired: 20_000_000e18, // More than 10M reserve
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            expectedEltaIn: type(uint256).max
        });

        // Case 6: Exact reserve (should return max)
        cases[5] = EltaInTestCase({
            name: "Exact reserve",
            tokensDesired: 10_000_000e18, // Equal to reserve
            reserveElta: 1000e18,
            reserveToken: 10_000_000e18,
            expectedEltaIn: type(uint256).max
        });

        return cases;
    }

    function test_Table_EltaInForTokens() public pure {
        EltaInTestCase[] memory cases = getEltaInTestCases();

        for (uint256 i = 0; i < cases.length; i++) {
            EltaInTestCase memory tc = cases[i];

            uint256 eltaIn = getEltaInForTokens(tc.tokensDesired, tc.reserveElta, tc.reserveToken);

            assertEq(eltaIn, tc.expectedEltaIn, string.concat(tc.name, ": eltaIn mismatch"));
        }
    }

    // =========== K Invariant Tests ===========

    struct KInvariantTestCase {
        string name;
        uint256 eltaIn;
        uint256 reserveElta;
        uint256 reserveToken;
    }

    function getKInvariantTestCases() internal pure returns (KInvariantTestCase[] memory) {
        KInvariantTestCase[] memory cases = new KInvariantTestCase[](5);

        cases[0] =
            KInvariantTestCase({name: "Small buy", eltaIn: 10e18, reserveElta: 1000e18, reserveToken: 10_000_000e18});

        cases[1] =
            KInvariantTestCase({name: "Medium buy", eltaIn: 100e18, reserveElta: 1000e18, reserveToken: 10_000_000e18});

        cases[2] =
            KInvariantTestCase({name: "Large buy", eltaIn: 500e18, reserveElta: 1000e18, reserveToken: 10_000_000e18});

        cases[3] =
            KInvariantTestCase({name: "Equal reserves", eltaIn: 100e18, reserveElta: 1000e18, reserveToken: 1000e18});

        cases[4] = KInvariantTestCase({
            name: "Large reserves", eltaIn: 1_000_000e18, reserveElta: 10_000_000e18, reserveToken: 100_000_000e18
        });

        return cases;
    }

    function test_Table_KInvariant() public pure {
        KInvariantTestCase[] memory cases = getKInvariantTestCases();

        for (uint256 i = 0; i < cases.length; i++) {
            KInvariantTestCase memory tc = cases[i];

            uint256 kBefore = tc.reserveElta * tc.reserveToken;
            uint256 tokensOut = getTokensOut(tc.eltaIn, tc.reserveElta, tc.reserveToken);
            uint256 kAfter = (tc.reserveElta + tc.eltaIn) * (tc.reserveToken - tokensOut);

            // k should decrease slightly due to integer division (buyer advantage)
            assertLe(kAfter, kBefore, string.concat(tc.name, ": k increased"));

            // k should not decrease by more than 1%
            assertGe(kAfter, (kBefore * 99) / 100, string.concat(tc.name, ": k decreased too much"));
        }
    }

    // =========== Helper Functions (matching contract implementation) ===========

    function getTokensOut(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken)
        internal
        pure
        returns (uint256 tokensOut)
    {
        if (eltaIn == 0 || reserveElta == 0 || reserveToken == 0) return 0;

        uint256 k = reserveElta * reserveToken;
        uint256 newReserveElta = reserveElta + eltaIn;
        uint256 newReserveToken = k / newReserveElta;

        tokensOut = reserveToken - newReserveToken;
    }

    function getCurrentPrice(uint256 reserveElta, uint256 reserveToken) internal pure returns (uint256 price) {
        if (reserveToken == 0) return 0;
        price = (reserveElta * 1e18) / reserveToken;
    }

    function getEltaInForTokens(uint256 tokensDesired, uint256 reserveElta, uint256 reserveToken)
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
}
