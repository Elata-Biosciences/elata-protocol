// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAppFeeRouter } from "../../src/interfaces/IAppFeeRouter.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";

/**
 * @title MockAppFeeRouter
 * @notice Mock fee router for testing
 */
contract MockAppFeeRouter is IAppFeeRouter {
    uint256 public override feeBps = 100; // 1%

    function takeAndForwardFee(address, uint256) external pure override {
        // Do nothing in mock
    }

    function calculateFee(uint256 amount) external view override returns (uint256) {
        return (amount * feeBps) / 10_000;
    }
}

/**
 * @title MockAppRewardsDistributor
 * @notice Mock rewards distributor for testing
 */
contract MockAppRewardsDistributor is IAppRewardsDistributor {
    address[] public registered;

    function registerApp(address vault) external override {
        registered.push(vault);
    }

    function distribute(uint256) external pure override {
        // Do nothing in mock
    }

    function claim(address, uint256) external pure {
        // Do nothing in mock
    }

    function getRegisteredCount() external view returns (uint256) {
        return registered.length;
    }
}
