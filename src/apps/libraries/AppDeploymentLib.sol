// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppBondingCurve} from "../AppBondingCurve.sol";
import {AppCurveDeployer} from "./AppCurveDeployer.sol";
import {AppTokenDeployer} from "./AppTokenDeployer.sol";
import {AppVaultDeployer} from "./AppVaultDeployer.sol";

/**
 * @title AppDeploymentLib
 * @notice Minimal library for deploying app contracts
 * @dev Delegates to specialized deployer libraries to reduce size
 */
library AppDeploymentLib {
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 supply,
        address creator,
        address factory,
        address governance,
        address appRewardsDistributor,
        address rewardsDistributor,
        address treasury
    ) external returns (address) {
        return AppTokenDeployer.deployToken(
            name,
            symbol,
            decimals,
            supply,
            creator,
            factory,
            governance,
            appRewardsDistributor,
            rewardsDistributor,
            treasury
        );
    }

    function deployVault(string calldata name, string calldata symbol, address token, address owner)
        external
        returns (address)
    {
        return AppVaultDeployer.deployVault(name, symbol, token, owner);
    }

    function deployCurve(AppBondingCurve.InitParams memory params) external returns (address) {
        return AppCurveDeployer.deployCurve(params);
    }
}
