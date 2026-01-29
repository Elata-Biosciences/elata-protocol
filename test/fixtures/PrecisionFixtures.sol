// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrecisionFixtures
 * @notice Shared fixtures and utilities for precision testing
 * @dev Provides dust amounts, boundary values, and helper functions
 *      for testing mathematical edge cases in the protocol
 */
abstract contract PrecisionFixtures {
    // =========== Dust Amount Fixtures ===========

    /// @notice Very small amounts for dust testing
    uint256[] public fixtureDustAmount = [
        1, // 1 wei
        2, // 2 wei
        10, // 10 wei
        100, // 100 wei
        1000, // 1000 wei
        1e6, // 1 million wei
        1e9, // 1 gwei
        1e12, // 1 szabo
        1e15 // 1 finney
    ];

    /// @notice Amounts that might cause precision loss in fee calculations
    uint256[] public fixturePrecisionEdgeAmount = [
        1, // Minimum
        99, // Below 100 (1 bps = 0)
        100, // Exactly 1 bps threshold
        101, // Just above
        999, // Below 10 bps threshold
        1000, // Exactly 10 bps
        9999, // Below 100 bps
        10000, // Exactly 100 bps (1%)
        99999, // Below 1000 bps
        100000 // 10%
    ];

    // =========== Basis Points Fixtures ===========

    /// @notice Fee percentages in basis points for edge case testing
    uint256[] public fixtureBasisPoints = [
        0, // 0%
        1, // 0.01% - minimum non-zero
        50, // 0.5%
        100, // 1%
        250, // 2.5%
        500, // 5%
        1000, // 10%
        2500, // 25%
        5000, // 50%
        7500, // 75%
        10000 // 100%
    ];

    // =========== Near-Overflow Fixtures ===========

    /// @notice Get values near uint256 max for overflow testing
    /// @dev Uses function instead of storage array to avoid constructor issues
    function getFixtureNearOverflow() public pure returns (uint256[] memory) {
        uint256[] memory values = new uint256[](8);
        values[0] = type(uint256).max;
        values[1] = type(uint256).max - 1;
        values[2] = type(uint256).max / 2;
        values[3] = type(uint256).max / 10;
        values[4] = type(uint128).max;
        values[5] = uint256(type(uint128).max) + 1;
        values[6] = type(uint96).max;
        values[7] = type(uint64).max;
        return values;
    }

    // =========== Decimal Conversion Fixtures ===========

    /// @notice ELTA amounts (18 decimals) for decimal conversion testing
    uint256[] public fixtureElta18Decimals = [
        1, // 1 wei ELTA
        1e6, // Dust that rounds to 0 USDC
        1e12, // 0.000001 ELTA
        1e15, // 0.001 ELTA
        1e18, // 1 ELTA
        1000e18, // 1000 ELTA
        1_000_000e18, // 1M ELTA
        77_000_000e18 // Max ELTA supply
    ];

    /// @notice USDC amounts (6 decimals) for decimal conversion testing
    uint256[] public fixtureUsdc6Decimals = [
        1, // 0.000001 USDC
        100, // 0.0001 USDC
        1e6, // 1 USDC
        1000e6, // 1000 USDC
        1_000_000e6 // 1M USDC
    ];

    // =========== Time Fixtures ===========

    /// @notice Time values for epoch/vesting edge cases
    uint256[] public fixtureTimeSeconds = [
        0, // Zero
        1, // Minimum
        60, // 1 minute
        3600, // 1 hour
        86400, // 1 day
        604800, // 1 week
        2592000, // 30 days
        7776000, // 90 days (typical cliff)
        31536000, // 365 days
        63072000 // 2 years
    ];

    // =========== Iteration Counts ===========

    /// @notice Iteration counts for accumulated error testing
    uint256[] public fixtureIterations = [10, 100, 500, 1000, 2500, 5000];

    // =========== Helper Functions ===========

    /// @notice Calculate fee with basis points (matching protocol implementation)
    function calculateFeeBps(uint256 amount, uint256 bps) public pure returns (uint256) {
        return (amount * bps) / 10000;
    }

    /// @notice Calculate multiple fee splits (matching FeeManager pattern)
    function calculateFeeSplits(
        uint256 amount,
        uint256 appStakersBps,
        uint256 veEltaBps,
        uint256 creatorBps,
        uint256 treasuryBps,
        uint256 referralBps
    )
        public
        pure
        returns (
            uint256 appShare,
            uint256 veShare,
            uint256 creatorShare,
            uint256 treasuryShare,
            uint256 referralShare,
            uint256 totalDistributed,
            uint256 roundingLoss
        )
    {
        appShare = (amount * appStakersBps) / 10000;
        veShare = (amount * veEltaBps) / 10000;
        creatorShare = (amount * creatorBps) / 10000;
        referralShare = (amount * referralBps) / 10000;
        // Treasury gets remainder to minimize dust
        treasuryShare = amount - appShare - veShare - creatorShare - referralShare;

        totalDistributed = appShare + veShare + creatorShare + treasuryShare + referralShare;
        roundingLoss = amount > totalDistributed ? amount - totalDistributed : 0;
    }

    /// @notice Calculate bonding curve tokens out (constant product formula)
    function calculateTokensOut(uint256 eltaIn, uint256 reserveElta, uint256 reserveToken)
        public
        pure
        returns (uint256 tokensOut, uint256 newK, uint256 kDrift)
    {
        if (eltaIn == 0 || reserveElta == 0 || reserveToken == 0) {
            return (0, 0, 0);
        }

        uint256 initialK = reserveElta * reserveToken;
        uint256 newReserveElta = reserveElta + eltaIn;
        uint256 newReserveToken = initialK / newReserveElta;

        tokensOut = reserveToken - newReserveToken;
        newK = newReserveElta * newReserveToken;
        kDrift = initialK > newK ? initialK - newK : 0;
    }

    /// @notice Convert 18-decimal to 6-decimal (ELTA to USDC scale)
    function convert18To6(uint256 amount18) public pure returns (uint256 amount6) {
        return amount18 / 1e12;
    }

    /// @notice Convert 6-decimal to 18-decimal (USDC to ELTA scale)
    function convert6To18(uint256 amount6) public pure returns (uint256 amount18) {
        return amount6 * 1e12;
    }

    /// @notice Check if a value would cause overflow when multiplied
    function wouldOverflow(uint256 a, uint256 b) public pure returns (bool) {
        if (a == 0 || b == 0) return false;
        return a > type(uint256).max / b;
    }

    /// @notice Calculate maximum safe multiplier for a value
    function maxSafeMultiplier(uint256 value) public pure returns (uint256) {
        if (value == 0) return type(uint256).max;
        return type(uint256).max / value;
    }

    /// @notice Generate pseudo-random amount within bounds (for iteration tests)
    function pseudoRandomAmount(uint256 seed, uint256 min, uint256 max) public pure returns (uint256) {
        if (max <= min) return min;
        return min + (uint256(keccak256(abi.encodePacked(seed))) % (max - min));
    }

    /// @notice Calculate share of total with precision tracking
    function calculateShareWithPrecision(uint256 userAmount, uint256 totalAmount, uint256 rewardAmount)
        public
        pure
        returns (uint256 share, uint256 precisionLoss)
    {
        if (totalAmount == 0) return (0, 0);

        // Calculate using same formula as protocol
        share = (rewardAmount * userAmount) / totalAmount;

        // Calculate what the exact share should be
        uint256 exactNumerator = rewardAmount * userAmount;
        uint256 remainder = exactNumerator % totalAmount;
        precisionLoss = remainder > 0 ? 1 : 0; // Lost at most 1 wei due to truncation
    }
}
