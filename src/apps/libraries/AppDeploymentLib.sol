// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppBondingCurve} from "../AppBondingCurve.sol";
import {AppToken} from "../AppToken.sol";
import {AppCurveDeployer} from "./AppCurveDeployer.sol";
import {AppTokenDeployer} from "./AppTokenDeployer.sol";
import {AppVaultDeployer} from "./AppVaultDeployer.sol";

/**
 * @title AppDeploymentLib
 * @notice Minimal library for deploying app contracts
 * @dev Delegates to specialized deployer libraries to reduce size
 */
library AppDeploymentLib {
    function deployToken(AppToken.InitParams memory params) external returns (address) {
        return AppTokenDeployer.deployToken(params);
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
