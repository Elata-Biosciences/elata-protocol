// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PrecisionFixtures} from "../fixtures/PrecisionFixtures.sol";

/**
 * @title MathPrecision
 * @notice Tests for mathematical precision edge cases across protocol
 * @dev Tests division boundaries, accumulated rounding, and basis point calculations
 *      Most tests are pure math tests that don't require contract deployment
 */
contract MathPrecision is Test, PrecisionFixtures {
    // Standard fee split from protocol: 45/30/10/10/5
    uint256 constant APP_STAKERS_BPS = 4500;
    uint256 constant VE_ELTA_BPS = 3000;
    uint256 constant CREATOR_BPS = 1000;
    uint256 constant TREASURY_BPS = 1000;
    uint256 constant REFERRAL_BPS = 500;

    function setUp() public {
        // No complex setup needed - most tests are pure math
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DIVISION EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test division by 1 (identity)
    function test_Math_DivisionByOne() public pure {
        uint256 amount = 1000e18;
        uint256 result = amount / 1;
        assertEq(result, amount, "Division by 1 should be identity");
    }

    /// @notice Test division resulting in zero
    function test_Math_DivisionResultsInZero() public pure {
        // Small numerator, large denominator
        uint256 numerator = 99;
        uint256 denominator = 10000;
        uint256 result = numerator / denominator;
        assertEq(result, 0, "Should truncate to zero");
    }

    /// @notice Test basis points on amounts below threshold
    function test_Math_BasisPointsBelowThreshold() public pure {
        // 1 bps (0.01%) on amounts < 10000 should yield 0
        for (uint256 i = 1; i < 10000; i += 1000) {
            uint256 feeLoop = (i * 1) / 10000;
            assertEq(feeLoop, 0, "Fee should be 0 for amounts below threshold");
        }

        // Exactly 10000 should yield 1
        uint256 feeThreshold = (10000 * 1) / 10000;
        assertEq(feeThreshold, 1, "Fee should be 1 at threshold");
    }

    /// @notice Fuzz test for basis point precision
    function testFuzz_Math_BasisPointsPrecision(uint256 amount, uint256 bps) public pure {
        amount = bound(amount, 1, 1e30);
        bps = bound(bps, 0, 10000);

        uint256 fee = (amount * bps) / 10000;

        // Fee should never exceed amount
        assertLe(fee, amount, "Fee exceeds amount");

        // Fee at 10000 bps should equal amount
        if (bps == 10000) {
            assertEq(fee, amount, "100% fee should equal amount");
        }

        // Fee at 0 bps should be 0
        if (bps == 0) {
            assertEq(fee, 0, "0% fee should be 0");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCUMULATED ROUNDING LOSS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test accumulated rounding loss over many fee split operations
    function test_Math_AccumulatedFeeSplitRounding() public pure {
        uint256 iterations = 1000;
        uint256 totalRoundingLoss = 0;

        // Standard fee split: 45/30/10/10/5
        uint256 appBps = 4500;
        uint256 veBps = 3000;
        uint256 creatorBps = 1000;
        uint256 treasuryBps = 1000;
        uint256 referralBps = 500;

        for (uint256 i = 1; i <= iterations; i++) {
            uint256 amount = i * 1e15; // Varying amounts

            uint256 appShare = (amount * appBps) / 10000;
            uint256 veShare = (amount * veBps) / 10000;
            uint256 creatorShare = (amount * creatorBps) / 10000;
            uint256 referralShare = (amount * referralBps) / 10000;
            uint256 treasuryShare = amount - appShare - veShare - creatorShare - referralShare;

            uint256 totalDistributed = appShare + veShare + creatorShare + treasuryShare + referralShare;

            if (totalDistributed < amount) {
                totalRoundingLoss += amount - totalDistributed;
            }
        }

        // With treasury getting remainder, there should be zero rounding loss
        assertEq(totalRoundingLoss, 0, "Treasury remainder should eliminate rounding loss");
    }

    /// @notice Fuzz test for accumulated rounding over many operations
    function testFuzz_Math_AccumulatedRoundingBounded(uint256 iterations) public pure {
        iterations = bound(iterations, 100, 2000);

        uint256 totalDeposited = 0;
        uint256 totalSplitOut = 0;

        for (uint256 i = 1; i <= iterations; i++) {
            uint256 amount = i * 1e14; // Small amounts that cause rounding
            totalDeposited += amount;

            // Simulate 5-way split
            uint256 share1 = (amount * 3000) / 10000;
            uint256 share2 = (amount * 2500) / 10000;
            uint256 share3 = (amount * 2000) / 10000;
            uint256 share4 = (amount * 1500) / 10000;
            uint256 share5 = amount - share1 - share2 - share3 - share4; // Remainder

            totalSplitOut += share1 + share2 + share3 + share4 + share5;
        }

        // Total should be conserved (remainder pattern)
        assertEq(totalSplitOut, totalDeposited, "Value should be conserved with remainder pattern");
    }

    /// @notice Test reward claim rounding over many users
    function test_Math_RewardClaimRoundingManyUsers() public pure {
        uint256 numUsers = 100;
        uint256 rewardPool = 1000e18;
        uint256 totalVotes = 10000e18;
        uint256 totalClaimed = 0;

        for (uint256 i = 1; i <= numUsers; i++) {
            uint256 userVotes = (totalVotes * i) / (numUsers * (numUsers + 1) / 2); // Varying stakes
            uint256 userClaim = (rewardPool * userVotes) / totalVotes;
            totalClaimed += userClaim;
        }

        // Total claimed should not exceed pool
        assertLe(totalClaimed, rewardPool, "Claims should not exceed pool");

        // Rounding loss should be bounded
        uint256 roundingLoss = rewardPool - totalClaimed;
        assertLe(roundingLoss, numUsers, "Rounding loss should be < 1 wei per user");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BONDING CURVE MATH PRECISION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test constant product formula precision
    function test_Math_ConstantProductPrecision() public pure {
        uint256 reserveElta = 1000e18;
        uint256 reserveToken = 10_000_000e18;
        uint256 initialK = reserveElta * reserveToken;

        // Simulate 100 buys
        for (uint256 i = 0; i < 100; i++) {
            uint256 eltaIn = 10e18;

            uint256 newReserveElta = reserveElta + eltaIn;
            uint256 newReserveToken = initialK / newReserveElta;
            uint256 tokensOut = reserveToken - newReserveToken;

            reserveElta = newReserveElta;
            reserveToken = newReserveToken;

            // k should only decrease (due to integer division favoring buyer)
            uint256 currentK = reserveElta * reserveToken;
            assertLe(currentK, initialK, "k should not increase");
        }

        // Final k should be within 1% of initial
        uint256 finalK = reserveElta * reserveToken;
        assertGe(finalK, (initialK * 99) / 100, "k drift should be < 1%");
    }

    /// @notice Fuzz test constant product invariant
    function testFuzz_Math_ConstantProductInvariant(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken) public {
        // Bound to reasonable values
        reserveElta = bound(reserveElta, 1e18, 100_000e18);
        reserveToken = bound(reserveToken, 1e18, 100_000_000e18);
        eltaIn = bound(eltaIn, 1e15, reserveElta / 10);

        (uint256 tokensOut, uint256 newK, uint256 kDrift) = calculateTokensOut(eltaIn, reserveElta, reserveToken);

        // k should only decrease
        uint256 initialK = reserveElta * reserveToken;
        assertLe(newK, initialK, "k increased");

        // Drift should be bounded (< 0.01% per trade)
        uint256 maxDrift = initialK / 10000;
        assertLe(kDrift, maxDrift, "k drift too large");

        // Tokens out should be positive and less than reserve
        assertGt(tokensOut, 0, "No tokens out");
        assertLt(tokensOut, reserveToken, "Tokens out >= reserve");
    }

    /// @notice Test price calculation at extreme reserves
    function test_Math_PriceAtExtremeReserves() public pure {
        // Very low token reserve (high price)
        uint256 reserveElta = 5000e18;
        uint256 reserveToken = 100e18; // Very few tokens left

        uint256 price = (reserveElta * 1e18) / reserveToken;
        assertEq(price, 50e18, "Price should be 50 ELTA per token");

        // Very high token reserve (low price)
        reserveToken = 10_000_000e18;
        price = (reserveElta * 1e18) / reserveToken;
        assertEq(price, 500000000000000, "Price should be 0.0005 ELTA per token");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DUST AMOUNT CALCULATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test fee calculation on dust amounts
    function test_Math_FeeOnDustAmounts() public view {
        for (uint256 i = 0; i < fixtureDustAmount.length; i++) {
            uint256 amount = fixtureDustAmount[i];
            uint256 fee100bps = (amount * 100) / 10000; // 1% fee

            // Fee should be floor of 1%
            assertEq(fee100bps, amount / 100, "Fee calculation incorrect");
        }
    }

    /// @notice Test that 1 wei amounts don't break calculations
    function test_Math_OneWeiHandling() public pure {
        uint256 amount = 1;

        // Fee split should not panic
        uint256 share1 = (amount * 4500) / 10000;
        uint256 share2 = (amount * 3000) / 10000;
        uint256 share3 = (amount * 1000) / 10000;
        uint256 share4 = (amount * 1000) / 10000;
        uint256 share5 = amount - share1 - share2 - share3 - share4;

        // All shares should be 0 except remainder
        assertEq(share1, 0, "Share1 should be 0");
        assertEq(share2, 0, "Share2 should be 0");
        assertEq(share3, 0, "Share3 should be 0");
        assertEq(share4, 0, "Share4 should be 0");
        assertEq(share5, 1, "Remainder should get the 1 wei");
    }

    /// @notice Test precision edge amounts from fixtures
    function test_Math_PrecisionEdgeAmounts() public view {
        for (uint256 i = 0; i < fixturePrecisionEdgeAmount.length; i++) {
            uint256 amount = fixturePrecisionEdgeAmount[i];

            // Calculate various fee percentages
            uint256 fee1bps = (amount * 1) / 10000;
            uint256 fee100bps = (amount * 100) / 10000;
            uint256 fee500bps = (amount * 500) / 10000;

            // Log for analysis
            console2.log("Amount:", amount);
            console2.log("  1 bps fee:", fee1bps);
            console2.log("  100 bps fee:", fee100bps);
            console2.log("  500 bps fee:", fee500bps);

            // Verify fees don't exceed amount
            assertLe(fee1bps + fee100bps + fee500bps, amount * 3, "Fees exceed bounds");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OVERFLOW PREVENTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test that large values don't overflow in fee calculations
    function test_Math_LargeValueNoOverflow() public pure {
        uint256 largeAmount = type(uint128).max;
        uint256 bps = 5000; // 50%

        // This should not overflow in Solidity 0.8+
        uint256 fee = (largeAmount * bps) / 10000;

        assertEq(fee, largeAmount / 2, "Large value fee calculation incorrect");
    }

    /// @notice Test overflow boundaries
    function test_Math_OverflowBoundaries() public view {
        // Find the max amount that doesn't overflow when multiplied by 10000
        uint256 maxSafeAmount = type(uint256).max / 10000;

        // This should work
        uint256 fee = (maxSafeAmount * 10000) / 10000;
        assertEq(fee, maxSafeAmount, "Safe amount calculation failed");

        // Verify our helper works
        assertTrue(wouldOverflow(maxSafeAmount + 1, 10000), "Should detect overflow");
        assertFalse(wouldOverflow(maxSafeAmount, 10000), "Should not overflow");
    }

    /// @notice Fuzz test for overflow safety
    function testFuzz_Math_NoOverflowOnFeeSplit(uint256 amount) public view {
        // Bound to safe range
        uint256 maxSafe = type(uint256).max / 10000;
        amount = bound(amount, 0, maxSafe);

        // These should not revert
        (
            uint256 appShare,
            uint256 veShare,
            uint256 creatorShare,
            uint256 treasuryShare,
            uint256 referralShare,
            uint256 totalDistributed,
        ) = calculateFeeSplits(amount, 4500, 3000, 1000, 1000, 500);

        // Verify conservation
        assertEq(totalDistributed, amount, "Value not conserved");
        assertEq(appShare + veShare + creatorShare + treasuryShare + referralShare, amount, "Shares don't sum");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SHARE CALCULATION PRECISION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test reward share calculation precision
    function test_Math_RewardSharePrecision() public pure {
        uint256 totalRewards = 1000e18;
        uint256 totalStaked = 10000e18;

        // User with 1 wei stake
        uint256 userStake = 1;
        uint256 userShare = (totalRewards * userStake) / totalStaked;

        // Should truncate to 0 for 1 wei out of 10000e18
        assertEq(userShare, 0, "Dust stake should get 0 rewards");

        // User with 1e18 stake (0.01%)
        userStake = 1e18;
        userShare = (totalRewards * userStake) / totalStaked;
        assertEq(userShare, 100e15, "1e18 stake should get 0.0001 of rewards");
    }

    /// @notice Test that sum of all shares equals total (within rounding)
    function testFuzz_Math_ShareSumEqualsTotal(uint256 numUsers, uint256 totalRewards) public pure {
        numUsers = bound(numUsers, 2, 50);
        totalRewards = bound(totalRewards, 1e18, 1_000_000e18);

        uint256 totalStaked = numUsers * 100e18; // Equal stakes
        uint256 stakePerUser = 100e18;

        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < numUsers; i++) {
            uint256 userShare = (totalRewards * stakePerUser) / totalStaked;
            totalClaimed += userShare;
        }

        // Due to integer division, rounding loss can be up to (numUsers - 1) wei
        // Example: 1000 / 3 = 333, 333 * 3 = 999 (loss of 1 wei)
        uint256 maxRoundingLoss = numUsers - 1;
        assertLe(totalRewards - totalClaimed, maxRoundingLoss, "Rounding loss should be bounded");
        assertGe(totalClaimed, totalRewards - maxRoundingLoss, "Total claimed should be close to total");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTEGRATION: FEE MANAGER PRECISION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test fee split precision using protocol constants
    function test_Integration_FeeSplitPrecision() public pure {
        // Verify protocol constants sum to 10000
        assertEq(
            APP_STAKERS_BPS + VE_ELTA_BPS + CREATOR_BPS + TREASURY_BPS + REFERRAL_BPS,
            10000,
            "Splits don't sum to 10000"
        );

        // Test with various amounts
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 1;
        testAmounts[1] = 100;
        testAmounts[2] = 10000;
        testAmounts[3] = 1e18;
        testAmounts[4] = 1_000_000e18;

        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];

            uint256 appShare = (amount * APP_STAKERS_BPS) / 10000;
            uint256 veShare = (amount * VE_ELTA_BPS) / 10000;
            uint256 creatorShare = (amount * CREATOR_BPS) / 10000;
            uint256 referralShare = (amount * REFERRAL_BPS) / 10000;
            uint256 treasuryShare = amount - appShare - veShare - creatorShare - referralShare;

            uint256 total = appShare + veShare + creatorShare + treasuryShare + referralShare;
            assertEq(total, amount, "Value not conserved for amount");
        }
    }
}
