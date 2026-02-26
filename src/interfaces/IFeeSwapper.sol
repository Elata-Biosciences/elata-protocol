// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeKind} from "../fees/FeeKind.sol";

/// @notice Minimal routing interface implemented by the unified `FeeSwapper`.
interface IFeeSwapper {
    event FeeAccrued(uint256 indexed appId, FeeKind indexed kind, address indexed asset, uint256 amount, address payer);
    event FeeRoutedToTreasury(uint256 indexed appId, FeeKind indexed kind, address indexed asset, uint256 amount);
    event FeeRoutedToContributors(
        uint256 indexed appId,
        FeeKind indexed kind,
        address indexed asset,
        uint256 contributorsAmount,
        address contributorSplit
    );

    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);
    event AppRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event AppTreasuryTakeUpdated(uint256 indexed appId, uint16 oldBps, uint16 newBps);
    event DefaultTreasuryTakeUpdated(uint16 oldBps, uint16 newBps);

    function accrue(uint256 appId, FeeKind kind, address asset, uint256 amount, address payer) external;
}

