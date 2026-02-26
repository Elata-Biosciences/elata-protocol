// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Explicit fee taxonomy used by FeeCollector/FeeRouterV2.
 * @dev Keeping fee "kinds" explicit prevents accidental yield-like routing.
 */
enum FeeKind {
    // Fee taxonomy used by FeeCollector/FeeSwapper.
    //
    // Routing policy (enforced in FeeSwapper):
    // - `LAUNCH_FEE` is protocol-owned and routes 100% to treasury.
    // - All other kinds are app revenue and route 80/20:
    //   - 80% to the app's ContributorSplit
    //   - 20% to Elata treasury
    // - If an app is paused in AppRegistry: 100% treasury (regardless of kind).
    LAUNCH_FEE,
    TRADING_FEE,
    TRANSFER_TAX,
    CONTENT_SALE,
    TOURNAMENT_FEE,
    OTHER
}

