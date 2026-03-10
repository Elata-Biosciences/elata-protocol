// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeKind} from "../fees/FeeKind.sol";

interface IContributorSplit {
    struct Contributor {
        address account;
        uint64 shares;
    }

    event ContributorSet(uint256 indexed appId, address indexed account, uint64 shares);
    event ContributorsReconfigured(uint256 indexed appId, uint256 contributorCount);

    event PaymentReceived(
        uint256 indexed appId, FeeKind indexed kind, address indexed asset, uint256 amount, address from
    );
    event PaymentReleased(uint256 indexed appId, address indexed asset, address indexed to, uint256 amount);

    event FeeRouterUpdated(uint256 indexed appId, address indexed oldRouter, address indexed newRouter);
    event OwnerSafeUpdated(uint256 indexed appId, address indexed oldOwnerSafe, address indexed newOwnerSafe);

    function appId() external view returns (uint256);
    function ownerSafe() external view returns (address);
    function feeRouter() external view returns (address);

    function contributorCount() external view returns (uint256);
    function maxContributors() external view returns (uint256);
    function sharesOf(address account) external view returns (uint64);
    function totalShares() external view returns (uint64);

    // App team management (Safe-controlled)
    function setContributors(Contributor[] calldata contributors) external;

    // Pull payouts
    function releasable(address asset, address account) external view returns (uint256);
    function release(address asset, address account) external;

    // Router entrypoint
    function onFeeReceived(FeeKind kind, address asset, uint256 amount, address from) external;
}

