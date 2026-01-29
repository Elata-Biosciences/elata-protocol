// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FuzzFixtures
 * @notice Provides fixture arrays for fuzz testing to ensure edge cases are covered
 * @dev Foundry will include these values in fuzz test inputs when parameter names match
 *      fixture array names (e.g., `fixtureAmount` matches parameter `amount`)
 */
abstract contract FuzzFixtures {
    // =========== Amount Fixtures ===========

    /// @notice Boundary values for token amounts
    uint256[] public fixtureAmount = [
        0, // Zero case
        1, // Minimum non-zero
        1e6, // USDC-scale amount
        1e18, // Standard ETH unit
        100e18, // Common test amount
        1_000_000e18, // Large amount
        type(uint96).max, // Max safe amount for many operations
        type(uint128).max, // Half max uint256
        type(uint256).max // Maximum possible
    ];

    /// @notice Smaller bounded amounts for operations that can't handle max values
    uint256[] public fixtureBoundedAmount = [0, 1, 1e18, 100e18, 10_000e18, 1_000_000e18];

    // =========== Fee Fixtures ===========

    /// @notice Fee values in basis points (0-10000)
    uint256[] public fixtureFeeBps = [
        0, // No fee
        1, // Minimum fee
        100, // 1%
        250, // 2.5%
        500, // 5%
        1000, // 10%
        1500, // 15% (typical max)
        10000 // 100% (edge case)
    ];

    /// @notice Protocol fee splits (must sum to 10000)
    uint256[] public fixtureFee = [0, 1, 100, 500, 1000, 2500, 5000, 10000];

    // =========== Duration Fixtures ===========

    /// @notice Time duration values in seconds
    uint256[] public fixtureDuration = [
        0, // Instant
        1, // Minimum
        1 hours, // Short
        1 days, // Daily
        7 days, // Weekly
        30 days, // Monthly
        90 days, // Quarterly
        365 days, // Annual
        2 * 365 days, // 2 years (common lock)
        4 * 365 days // 4 years (max veELTA lock)
    ];

    /// @notice Lock durations for veELTA
    uint256[] public fixtureLockDuration = [
        7 days, // Minimum lock
        30 days, // 1 month
        180 days, // 6 months
        365 days, // 1 year
        2 * 365 days, // 2 years
        4 * 365 days // Max lock (4 years)
    ];

    // =========== Address Fixtures ===========

    /// @notice Special addresses for testing
    function fixtureAddress() public pure returns (address[] memory) {
        address[] memory addrs = new address[](5);
        addrs[0] = address(0); // Zero address
        addrs[1] = address(1); // Precompile range
        addrs[2] = address(0xdead); // Burn address
        addrs[3] = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF); // Max address
        addrs[4] = address(uint160(uint256(keccak256("user")))); // Random user
        return addrs;
    }

    // =========== Percentage Fixtures ===========

    /// @notice Percentage values (0-100 scaled to 1e18)
    uint256[] public fixturePercentage = [
        0,
        1e16, // 1%
        5e16, // 5%
        10e16, // 10%
        25e16, // 25%
        50e16, // 50%
        75e16, // 75%
        100e16 // 100%
    ];

    // =========== App ID Fixtures ===========

    /// @notice App IDs for testing
    uint256[] public fixtureAppId = [0, 1, 2, 10, 100, 1000, type(uint256).max];

    // =========== Token Supply Fixtures ===========

    /// @notice Token supply values
    uint256[] public fixtureSupply = [
        1e18, // Minimum viable
        1_000_000e18, // 1M tokens
        10_000_000e18, // 10M tokens (typical app)
        100_000_000e18, // 100M tokens
        77_000_000e18 // ELTA max supply
    ];

    // =========== Price Fixtures ===========

    /// @notice Price values for bonding curve testing
    uint256[] public fixturePrice = [
        1, // Minimum
        1e6, // USDC scale
        1e18, // ETH scale
        100e18, // $100
        1000e18, // $1000
        type(uint128).max // Very high price
    ];
}
